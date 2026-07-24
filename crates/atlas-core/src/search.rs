use ignore::WalkBuilder;
use notify::{Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::{BufReader, BufWriter};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering as AtomicOrdering};
use std::sync::{mpsc, Arc, Mutex, RwLock};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, UNIX_EPOCH};
use thiserror::Error;

const FILE_NAMESPACE: &str = "files";
const CACHE_VERSION: u32 = 3;
const MAX_INDEXED_ENTRIES: usize = 1_000_000;
const CACHE_MAX_AGE: Duration = Duration::from_secs(24 * 60 * 60);

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct SearchDocument {
    pub id: String,
    pub namespace: String,
    pub title: String,
    pub subtitle: String,
    pub keywords: Vec<String>,
    pub path: String,
    pub kind: String,
    pub modified_at: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchHit {
    pub document: SearchDocument,
    pub score: i64,
    pub title_highlight_offsets: Vec<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FileIndexPhase {
    Idle,
    Loading,
    Scanning,
    Ready,
    Error,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FileIndexStatus {
    pub phase: FileIndexPhase,
    pub indexed_count: u64,
    pub last_error: Option<String>,
}

impl Default for FileIndexStatus {
    fn default() -> Self {
        Self {
            phase: FileIndexPhase::Idle,
            indexed_count: 0,
            last_error: None,
        }
    }
}

#[derive(Debug, Error)]
pub enum SearchError {
    #[error("search index lock is poisoned")]
    LockPoisoned,
    #[error("no valid search roots were provided")]
    NoValidRoots,
    #[error("failed to start file index worker: {0}")]
    WorkerStart(String),
}

#[derive(Default)]
pub struct SearchIndex {
    documents: RwLock<HashMap<String, IndexedDocument>>,
}

struct IndexedDocument {
    document: SearchDocument,
    title: String,
    subtitle: String,
    path: String,
    keywords: Vec<String>,
}

impl IndexedDocument {
    fn new(document: SearchDocument) -> Self {
        let is_file = document.namespace == FILE_NAMESPACE;
        Self {
            title: normalize(&document.title),
            subtitle: if is_file {
                String::new()
            } else {
                normalize(&document.subtitle)
            },
            path: if is_file {
                String::new()
            } else {
                normalize(&document.path)
            },
            keywords: if is_file {
                Vec::new()
            } else {
                document
                    .keywords
                    .iter()
                    .map(|keyword| normalize(keyword))
                    .collect()
            },
            document,
        }
    }
}

impl SearchIndex {
    pub fn replace_namespace(
        &self,
        namespace: &str,
        documents: Vec<SearchDocument>,
    ) -> Result<(), SearchError> {
        let mut index = self
            .documents
            .write()
            .map_err(|_| SearchError::LockPoisoned)?;
        index.retain(|_, document| document.document.namespace != namespace);
        for document in documents {
            index.insert(document.id.clone(), IndexedDocument::new(document));
        }
        Ok(())
    }

    pub fn upsert(&self, document: SearchDocument) -> Result<(), SearchError> {
        self.documents
            .write()
            .map_err(|_| SearchError::LockPoisoned)?
            .insert(document.id.clone(), IndexedDocument::new(document));
        Ok(())
    }

    pub fn remove_path(&self, path: &Path) -> Result<(), SearchError> {
        let path = path.to_string_lossy();
        let descendant_prefix = format!("{path}/");
        self.documents
            .write()
            .map_err(|_| SearchError::LockPoisoned)?
            .retain(|_, document| {
                document.document.namespace != FILE_NAMESPACE
                    || (document.document.path != path
                        && !document.document.path.starts_with(&descendant_prefix))
            });
        Ok(())
    }

    pub fn namespace_documents(&self, namespace: &str) -> Result<Vec<SearchDocument>, SearchError> {
        Ok(self
            .documents
            .read()
            .map_err(|_| SearchError::LockPoisoned)?
            .values()
            .filter(|document| document.document.namespace == namespace)
            .map(|document| document.document.clone())
            .collect())
    }

    pub fn count_namespace(&self, namespace: &str) -> Result<usize, SearchError> {
        Ok(self
            .documents
            .read()
            .map_err(|_| SearchError::LockPoisoned)?
            .values()
            .filter(|document| document.document.namespace == namespace)
            .count())
    }

    pub fn search(
        &self,
        query: &str,
        limit: usize,
        namespaces: &[String],
    ) -> Result<Vec<SearchHit>, SearchError> {
        let terms = parse_query(query);
        if terms.is_empty() || limit == 0 {
            return Ok(Vec::new());
        }

        let index = self
            .documents
            .read()
            .map_err(|_| SearchError::LockPoisoned)?;
        let mut hits = index
            .values()
            .filter(|document| {
                namespaces.is_empty() || namespaces.contains(&document.document.namespace)
            })
            .filter_map(|document| {
                score_document(document, &terms).map(|result| SearchHit {
                    document: document.document.clone(),
                    score: result.score,
                    title_highlight_offsets: result.title_highlight_offsets,
                })
            })
            .collect::<Vec<_>>();

        hits.sort_unstable_by(|lhs, rhs| {
            rhs.score
                .cmp(&lhs.score)
                .then_with(|| rhs.document.modified_at.cmp(&lhs.document.modified_at))
                .then_with(|| lhs.document.title.len().cmp(&rhs.document.title.len()))
                .then_with(|| lhs.document.path.cmp(&rhs.document.path))
        });
        hits.truncate(limit);
        Ok(hits)
    }
}

/// Ranks an ephemeral candidate set without mutating the long-lived catalog.
///
/// Launcher providers use this path so every command, app, snippet, and note
/// shares the exact same matcher while the persistent file namespace continues
/// updating independently.
pub fn rank_documents(
    documents: Vec<SearchDocument>,
    query: &str,
    limit: usize,
) -> Result<Vec<SearchHit>, SearchError> {
    let index = SearchIndex::default();
    for document in documents {
        index.upsert(document)?;
    }
    index.search(query, limit, &[])
}

pub struct SearchService {
    index: Arc<SearchIndex>,
    file_status: Arc<Mutex<FileIndexStatus>>,
    worker: Mutex<Option<FileIndexWorker>>,
}

impl Default for SearchService {
    fn default() -> Self {
        Self::new()
    }
}

impl SearchService {
    pub fn new() -> Self {
        Self {
            index: Arc::new(SearchIndex::default()),
            file_status: Arc::new(Mutex::new(FileIndexStatus::default())),
            worker: Mutex::new(None),
        }
    }

    pub fn replace_namespace(
        &self,
        namespace: &str,
        documents: Vec<SearchDocument>,
    ) -> Result<(), SearchError> {
        self.index.replace_namespace(namespace, documents)
    }

    pub fn search(
        &self,
        query: &str,
        limit: usize,
        namespaces: &[String],
    ) -> Result<Vec<SearchHit>, SearchError> {
        self.index.search(query, limit, namespaces)
    }

    pub fn start_file_index(
        &self,
        roots: Vec<PathBuf>,
        cache_path: PathBuf,
    ) -> Result<(), SearchError> {
        self.stop_file_index()?;

        let roots = roots
            .into_iter()
            .filter_map(|path| path.canonicalize().ok())
            .filter(|path| path.is_dir())
            .collect::<Vec<_>>();
        if roots.is_empty() {
            return Err(SearchError::NoValidRoots);
        }

        set_status(
            &self.file_status,
            FileIndexPhase::Loading,
            self.index.count_namespace(FILE_NAMESPACE).unwrap_or(0),
            None,
        );

        let cancel = Arc::new(AtomicBool::new(false));
        let worker_cancel = Arc::clone(&cancel);
        let index = Arc::clone(&self.index);
        let status = Arc::clone(&self.file_status);
        let handle = thread::Builder::new()
            .name("atlas-file-index".to_string())
            .spawn(move || {
                run_file_index_worker(index, status, roots, cache_path, worker_cancel);
            })
            .map_err(|error| SearchError::WorkerStart(error.to_string()))?;

        *self.worker.lock().map_err(|_| SearchError::LockPoisoned)? =
            Some(FileIndexWorker { cancel, handle });
        Ok(())
    }

    pub fn stop_file_index(&self) -> Result<(), SearchError> {
        let worker = self
            .worker
            .lock()
            .map_err(|_| SearchError::LockPoisoned)?
            .take();
        if let Some(worker) = worker {
            worker.cancel.store(true, AtomicOrdering::Relaxed);
            let _ = worker.handle.join();
        }
        Ok(())
    }

    pub fn file_status(&self) -> Result<FileIndexStatus, SearchError> {
        self.file_status
            .lock()
            .map_err(|_| SearchError::LockPoisoned)
            .map(|status| status.clone())
    }
}

struct FileIndexWorker {
    cancel: Arc<AtomicBool>,
    handle: JoinHandle<()>,
}

#[derive(Serialize, Deserialize)]
struct FileIndexCache {
    version: u32,
    roots: Vec<String>,
    documents: Vec<SearchDocument>,
}

fn run_file_index_worker(
    index: Arc<SearchIndex>,
    status: Arc<Mutex<FileIndexStatus>>,
    roots: Vec<PathBuf>,
    cache_path: PathBuf,
    cancel: Arc<AtomicBool>,
) {
    let root_strings = roots
        .iter()
        .map(|path| path.to_string_lossy().into_owned())
        .collect::<Vec<_>>();

    let cache_is_fresh = cache_age_is_within(&cache_path, CACHE_MAX_AGE);
    let loaded_cache = if let Some(documents) = load_cache(&cache_path, &root_strings) {
        let count = documents.len();
        let _ = index.replace_namespace(FILE_NAMESPACE, documents);
        set_status(
            &status,
            if cache_is_fresh {
                FileIndexPhase::Ready
            } else {
                FileIndexPhase::Scanning
            },
            count,
            None,
        );
        true
    } else {
        set_status(&status, FileIndexPhase::Scanning, 0, None);
        false
    };

    let (event_tx, event_rx) = mpsc::channel();
    let watcher = match create_watcher(&roots, event_tx) {
        Ok(watcher) => watcher,
        Err(error) => {
            set_status(
                &status,
                FileIndexPhase::Error,
                index.count_namespace(FILE_NAMESPACE).unwrap_or(0),
                Some(error),
            );
            return;
        }
    };

    if !loaded_cache || !cache_is_fresh {
        match scan_roots(&roots, &cancel) {
            Ok(documents) if !cancel.load(AtomicOrdering::Relaxed) => {
                let count = documents.len();
                let _ = index.replace_namespace(FILE_NAMESPACE, documents.clone());
                let _ = save_cache(&cache_path, &root_strings, documents);
                set_status(&status, FileIndexPhase::Ready, count, None);
            }
            Ok(_) => return,
            Err(error) => {
                set_status(
                    &status,
                    FileIndexPhase::Error,
                    index.count_namespace(FILE_NAMESPACE).unwrap_or(0),
                    Some(error),
                );
            }
        }
    }

    let mut dirty = false;
    let mut last_change = Instant::now();
    while !cancel.load(AtomicOrdering::Relaxed) {
        match event_rx.recv_timeout(Duration::from_millis(250)) {
            Ok(Ok(event)) => {
                if apply_event(&index, &roots, event, &cancel) {
                    dirty = true;
                    last_change = Instant::now();
                }
            }
            Ok(Err(error)) => {
                set_status(
                    &status,
                    FileIndexPhase::Error,
                    index.count_namespace(FILE_NAMESPACE).unwrap_or(0),
                    Some(error.to_string()),
                );
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }

        if dirty && last_change.elapsed() >= Duration::from_secs(5) {
            if let Ok(documents) = index.namespace_documents(FILE_NAMESPACE) {
                let _ = save_cache(&cache_path, &root_strings, documents);
            }
            dirty = false;
        }
    }

    drop(watcher);
    if dirty {
        if let Ok(documents) = index.namespace_documents(FILE_NAMESPACE) {
            let _ = save_cache(&cache_path, &root_strings, documents);
        }
    }
}

fn create_watcher(
    roots: &[PathBuf],
    event_tx: mpsc::Sender<notify::Result<Event>>,
) -> Result<RecommendedWatcher, String> {
    let mut watcher = notify::recommended_watcher(move |event| {
        let _ = event_tx.send(event);
    })
    .map_err(|error| error.to_string())?;
    for root in roots {
        watcher
            .watch(root, RecursiveMode::Recursive)
            .map_err(|error| error.to_string())?;
    }
    Ok(watcher)
}

fn scan_roots(roots: &[PathBuf], cancel: &AtomicBool) -> Result<Vec<SearchDocument>, String> {
    let mut documents = Vec::new();
    for root in roots {
        let mut builder = WalkBuilder::new(root);
        builder
            .standard_filters(true)
            .hidden(true)
            .follow_links(false)
            .add_custom_ignore_filename(".atlasignore")
            .filter_entry(|entry| !is_noisy_path(entry.path()));

        for result in builder.build() {
            if cancel.load(AtomicOrdering::Relaxed) {
                return Ok(Vec::new());
            }
            let entry = match result {
                Ok(entry) => entry,
                Err(_) => continue,
            };
            if entry.path() == root || documents.len() >= MAX_INDEXED_ENTRIES {
                continue;
            }
            if let Some(document) = document_for_path(entry.path()) {
                documents.push(document);
            }
        }
    }
    Ok(documents)
}

fn apply_event(index: &SearchIndex, roots: &[PathBuf], event: Event, cancel: &AtomicBool) -> bool {
    if event.paths.iter().any(|path| is_ignore_file(path)) {
        if let Ok(documents) = scan_roots(roots, cancel) {
            return index.replace_namespace(FILE_NAMESPACE, documents).is_ok();
        }
        return false;
    }

    let scan_directories = matches!(&event.kind, EventKind::Create(_));
    match event.kind {
        EventKind::Remove(_) => {
            let mut changed = false;
            for path in event.paths {
                if is_noisy_path(&path) || roots.iter().any(|root| root == &path) {
                    continue;
                }
                let _ = index.remove_path(&path);
                changed = true;
            }
            changed
        }
        EventKind::Create(_) | EventKind::Modify(_) | EventKind::Any => {
            let mut changed = false;
            for path in event.paths {
                if is_noisy_path(&path) || roots.iter().any(|root| root == &path) {
                    continue;
                }
                if !path.exists() {
                    let _ = index.remove_path(&path);
                    changed = true;
                    continue;
                }
                if path.is_dir() {
                    if scan_directories {
                        if let Ok(documents) = scan_roots(&[path.clone()], cancel) {
                            for document in documents {
                                let _ = index.upsert(document);
                                changed = true;
                            }
                        }
                    }
                    continue;
                }
                if let Some(document) = document_for_path(&path) {
                    let _ = index.upsert(document);
                    changed = true;
                }
            }
            changed
        }
        _ => false,
    }
}

fn document_for_path(path: &Path) -> Option<SearchDocument> {
    if is_noisy_path(path) {
        return None;
    }
    let metadata = fs::symlink_metadata(path).ok()?;
    if metadata.file_type().is_symlink() {
        return None;
    }
    let title = path.file_name()?.to_string_lossy().into_owned();
    if title.is_empty() || title.starts_with('.') {
        return None;
    }
    let path_string = path.to_string_lossy().into_owned();
    let modified_at = metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |duration| duration.as_secs());
    Some(SearchDocument {
        id: format!("file:{path_string}"),
        namespace: FILE_NAMESPACE.to_string(),
        title,
        subtitle: path
            .parent()
            .map_or_else(String::new, |parent| parent.to_string_lossy().into_owned()),
        keywords: Vec::new(),
        path: path_string,
        kind: if metadata.is_dir() {
            "folder".to_string()
        } else {
            "file".to_string()
        },
        modified_at,
    })
}

#[derive(Clone, Debug)]
struct DocumentScore {
    score: i64,
    title_highlight_offsets: Vec<u32>,
}

#[derive(Clone, Debug)]
struct TextScore {
    score: i64,
    positions: Vec<usize>,
}

#[derive(Clone, Copy, Debug)]
enum MatchMode {
    Fuzzy,
    Exact,
    Prefix,
    Suffix,
    Equal,
}

#[derive(Clone, Debug)]
struct QueryAlternative {
    text: String,
    characters: Vec<char>,
    mode: MatchMode,
}

#[derive(Clone, Debug)]
struct QueryTerm {
    excluded: bool,
    alternatives: Vec<QueryAlternative>,
}

fn score_document(document: &IndexedDocument, terms: &[QueryTerm]) -> Option<DocumentScore> {
    let mut total_score = 0;
    let mut title_highlights = Vec::new();

    for term in terms {
        let mut best: Option<(TextScore, bool)> = None;
        for alternative in &term.alternatives {
            consider_match(&mut best, score_text(&document.title, alternative), 0, true);
            if document.document.namespace != FILE_NAMESPACE {
                consider_match(
                    &mut best,
                    score_text(&document.subtitle, alternative),
                    -1_000,
                    false,
                );
                consider_match(
                    &mut best,
                    score_text(&document.path, alternative),
                    -1_500,
                    false,
                );
            }
            for keyword in &document.keywords {
                consider_match(&mut best, score_text(keyword, alternative), -500, false);
            }
        }

        if term.excluded {
            if best.is_some() {
                return None;
            }
            continue;
        }
        let (best, is_title) = best?;
        total_score += best.score;
        if is_title {
            title_highlights.extend(best.positions.into_iter().map(|position| position as u32));
        }
    }

    title_highlights.sort_unstable();
    title_highlights.dedup();
    Some(DocumentScore {
        score: total_score,
        title_highlight_offsets: title_highlights,
    })
}

fn consider_match(
    best: &mut Option<(TextScore, bool)>,
    candidate: Option<TextScore>,
    adjustment: i64,
    is_title: bool,
) {
    let Some(mut candidate) = candidate else {
        return;
    };
    candidate.score += adjustment;
    if best
        .as_ref()
        .is_none_or(|(current, _)| candidate.score > current.score)
    {
        *best = Some((candidate, is_title));
    }
}

fn parse_query(query: &str) -> Vec<QueryTerm> {
    query
        .split_whitespace()
        .filter_map(|raw_term| {
            let (excluded, value) = raw_term
                .strip_prefix('!')
                .map_or((false, raw_term), |value| (true, value));
            let alternatives = value
                .split('|')
                .filter_map(|raw_alternative| {
                    let mut value = raw_alternative;
                    let mut mode = MatchMode::Fuzzy;
                    if let Some(stripped) = value.strip_prefix('\'') {
                        value = stripped;
                        mode = MatchMode::Exact;
                    } else if let Some(stripped) = value.strip_prefix('^') {
                        value = stripped;
                        mode = MatchMode::Prefix;
                    }
                    if let Some(stripped) = value.strip_suffix('$') {
                        value = stripped;
                        mode = if matches!(mode, MatchMode::Prefix) {
                            MatchMode::Equal
                        } else {
                            MatchMode::Suffix
                        };
                    }
                    (!value.is_empty()).then(|| {
                        let text = normalize(value);
                        QueryAlternative {
                            characters: text.chars().collect(),
                            text,
                            mode,
                        }
                    })
                })
                .collect::<Vec<_>>();
            (!alternatives.is_empty()).then_some(QueryTerm {
                excluded,
                alternatives,
            })
        })
        .collect()
}

fn score_text(candidate: &str, alternative: &QueryAlternative) -> Option<TextScore> {
    let query = &alternative.text;
    let query_chars = &alternative.characters;
    if query_chars.is_empty() {
        return None;
    }

    let (bonus, positions) = match alternative.mode {
        MatchMode::Fuzzy => {
            if candidate == query {
                (3_000, (0..query_chars.len()).collect())
            } else if candidate.starts_with(query) {
                (
                    2_000 - candidate.chars().count() as i64,
                    (0..query_chars.len()).collect(),
                )
            } else if let Some(position) = word_prefix_position(candidate, query) {
                (
                    1_500 - position as i64,
                    (position..position + query_chars.len()).collect(),
                )
            } else if let Some(position) = boundary_contiguous_position(candidate, query) {
                (
                    1_000 - position as i64,
                    (position..position + query_chars.len()).collect(),
                )
            } else {
                let positions = bounded_fuzzy_positions(candidate, query_chars)?;
                let span = positions.last()? - positions.first()? + 1;
                (200 - span as i64, positions)
            }
        }
        MatchMode::Exact => {
            let position = contiguous_position(candidate, query)?;
            (
                2_200 - position as i64,
                (position..position + query_chars.len()).collect(),
            )
        }
        MatchMode::Prefix => {
            if !candidate.starts_with(query) {
                return None;
            }
            (2_500, (0..query_chars.len()).collect())
        }
        MatchMode::Suffix => {
            if !candidate.ends_with(query) {
                return None;
            }
            let position = candidate.chars().count().checked_sub(query_chars.len())?;
            (2_300, (position..position + query_chars.len()).collect())
        }
        MatchMode::Equal => {
            if candidate != query {
                return None;
            }
            (3_000, (0..query_chars.len()).collect())
        }
    };

    Some(TextScore {
        score: 10_000 + bonus,
        positions,
    })
}

fn word_prefix_position(candidate: &str, query: &str) -> Option<usize> {
    candidate.match_indices(query).find_map(|(byte_offset, _)| {
        let at_boundary = byte_offset == 0
            || candidate[..byte_offset]
                .chars()
                .next_back()
                .is_some_and(|character| !character.is_alphanumeric());
        at_boundary.then(|| candidate[..byte_offset].chars().count())
    })
}

fn contiguous_position(candidate: &str, query: &str) -> Option<usize> {
    candidate
        .find(query)
        .map(|byte_offset| candidate[..byte_offset].chars().count())
}

fn boundary_contiguous_position(candidate: &str, query: &str) -> Option<usize> {
    let query_length = query.chars().count();
    candidate.match_indices(query).find_map(|(byte_offset, _)| {
        let at_boundary = query_length < 3
            || byte_offset == 0
            || candidate[..byte_offset]
                .chars()
                .next_back()
                .is_some_and(|character| !character.is_alphanumeric());
        at_boundary.then(|| candidate[..byte_offset].chars().count())
    })
}

fn bounded_fuzzy_positions(candidate: &str, query: &[char]) -> Option<Vec<usize>> {
    if query.len() < 2 {
        return None;
    }
    let mut positions = Vec::with_capacity(query.len());
    let mut query_index = 0;
    let mut first_previous = None;
    let mut previous = None;
    for (index, character) in candidate.chars().enumerate() {
        if character == query[query_index] {
            if positions.is_empty() {
                first_previous = previous;
            }
            positions.push(index);
            query_index += 1;
            if query_index == query.len() {
                break;
            }
        }
        previous = Some(character);
    }
    if query_index != query.len() {
        return None;
    }
    let first = *positions.first()?;
    let last = *positions.last()?;
    let starts_at_boundary =
        first == 0 || first_previous.is_some_and(|value| !value.is_alphanumeric());
    let span = last - first + 1;
    (starts_at_boundary && span <= query.len() * 2 + 1).then_some(positions)
}

fn normalize(value: &str) -> String {
    value.trim().to_lowercase()
}

fn is_noisy_path(path: &Path) -> bool {
    let noisy_component = path.components().any(|component| {
        matches!(
            component.as_os_str().to_str(),
            Some(
                "node_modules"
                    | "target"
                    | ".build"
                    | "DerivedData"
                    | "__pycache__"
                    | ".Trash"
                    | "Caches"
                    | "Library"
            )
        )
    });
    let package = path
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "app"
                    | "bundle"
                    | "framework"
                    | "photoslibrary"
                    | "photolibrary"
                    | "musiclibrary"
                    | "imovielibrary"
            )
        });
    noisy_component || package
}

fn is_ignore_file(path: &Path) -> bool {
    matches!(
        path.file_name().and_then(|name| name.to_str()),
        Some(".gitignore" | ".ignore" | ".atlasignore")
    )
}

fn load_cache(cache_path: &Path, roots: &[String]) -> Option<Vec<SearchDocument>> {
    let file = File::open(cache_path).ok()?;
    let cache: FileIndexCache = bincode::deserialize_from(BufReader::new(file)).ok()?;
    (cache.version == CACHE_VERSION && cache.roots == roots).then_some(cache.documents)
}

fn cache_age_is_within(cache_path: &Path, maximum_age: Duration) -> bool {
    fs::metadata(cache_path)
        .and_then(|metadata| metadata.modified())
        .ok()
        .and_then(|modified| modified.elapsed().ok())
        .is_some_and(|age| age <= maximum_age)
}

fn save_cache(
    cache_path: &Path,
    roots: &[String],
    documents: Vec<SearchDocument>,
) -> Result<(), String> {
    if let Some(parent) = cache_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    let temporary_path = cache_path.with_extension("tmp");
    let file = File::create(&temporary_path).map_err(|error| error.to_string())?;
    bincode::serialize_into(
        BufWriter::new(file),
        &FileIndexCache {
            version: CACHE_VERSION,
            roots: roots.to_vec(),
            documents,
        },
    )
    .map_err(|error| error.to_string())?;
    fs::rename(temporary_path, cache_path).map_err(|error| error.to_string())
}

fn set_status(
    status: &Mutex<FileIndexStatus>,
    phase: FileIndexPhase,
    indexed_count: usize,
    last_error: Option<String>,
) {
    if let Ok(mut status) = status.lock() {
        status.phase = phase;
        status.indexed_count = indexed_count as u64;
        status.last_error = last_error;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn document(id: &str, namespace: &str, title: &str, path: &str) -> SearchDocument {
        SearchDocument {
            id: id.to_string(),
            namespace: namespace.to_string(),
            title: title.to_string(),
            subtitle: String::new(),
            keywords: Vec::new(),
            path: path.to_string(),
            kind: "command".to_string(),
            modified_at: 0,
        }
    }

    #[test]
    fn ranks_prefix_above_word_prefix_and_rejects_mid_word_contains() {
        let index = SearchIndex::default();
        index
            .replace_namespace(
                "commands",
                vec![
                    document("prefix", "commands", "Test Runner", ""),
                    document("word", "commands", "Run Test", ""),
                    document("contains", "commands", "Latest", ""),
                ],
            )
            .unwrap();

        let hits = index.search("tes", 10, &[]).unwrap();
        assert_eq!(
            hits.iter()
                .map(|hit| hit.document.id.as_str())
                .collect::<Vec<_>>(),
            vec!["prefix", "word"]
        );
    }

    #[test]
    fn rejects_sparse_fuzzy_matches() {
        let index = SearchIndex::default();
        index
            .replace_namespace(
                "apps",
                vec![
                    document("table", "apps", "TablePlus", ""),
                    document("notes", "commands", "Copy Meeting Notes", ""),
                ],
            )
            .unwrap();
        assert!(index.search("tes", 10, &[]).unwrap().is_empty());
    }

    #[test]
    fn supports_multi_term_and_operator_queries() {
        let index = SearchIndex::default();
        let mut settings = document("settings", "commands", "Open Settings", "");
        settings.subtitle = "System".to_string();
        index
            .replace_namespace(
                "commands",
                vec![
                    document("area", "commands", "Capture Area", ""),
                    document("window", "commands", "Capture Window", ""),
                    settings,
                ],
            )
            .unwrap();

        assert_eq!(
            index
                .search("^capture !window", 10, &[])
                .unwrap()
                .into_iter()
                .map(|hit| hit.document.id)
                .collect::<Vec<_>>(),
            vec!["area"]
        );
        assert_eq!(
            index
                .search("area|window", 10, &[])
                .unwrap()
                .into_iter()
                .map(|hit| hit.document.id)
                .collect::<Vec<_>>(),
            vec!["area", "window"]
        );
        assert_eq!(
            index
                .search("open system", 10, &[])
                .unwrap()
                .into_iter()
                .map(|hit| hit.document.id)
                .collect::<Vec<_>>(),
            vec!["settings"]
        );
    }

    #[test]
    fn scan_honors_ignore_files_and_noisy_directories() {
        let root = tempdir().unwrap();
        fs::write(root.path().join("visible.txt"), "ok").unwrap();
        fs::write(root.path().join(".hidden.txt"), "hidden").unwrap();
        fs::create_dir(root.path().join("node_modules")).unwrap();
        fs::write(root.path().join("node_modules/package.js"), "ignored").unwrap();
        fs::create_dir(root.path().join("ignored")).unwrap();
        fs::write(root.path().join("ignored/secret.txt"), "ignored").unwrap();
        fs::write(root.path().join(".atlasignore"), "ignored/\n").unwrap();

        let documents = scan_roots(&[root.path().to_path_buf()], &AtomicBool::new(false)).unwrap();
        let titles = documents
            .iter()
            .map(|document| document.title.as_str())
            .collect::<Vec<_>>();
        assert!(titles.contains(&"visible.txt"));
        assert!(!titles.contains(&".hidden.txt"));
        assert!(!titles.contains(&"package.js"));
        assert!(!titles.contains(&"secret.txt"));
    }

    #[test]
    fn cache_round_trip_requires_matching_roots() {
        let root = tempdir().unwrap();
        let cache_path = root.path().join("index.json");
        let roots = vec![root.path().to_string_lossy().into_owned()];
        let documents = vec![document("one", FILE_NAMESPACE, "One.txt", "/tmp/One.txt")];

        save_cache(&cache_path, &roots, documents.clone()).unwrap();
        assert_eq!(load_cache(&cache_path, &roots), Some(documents));
        assert!(load_cache(&cache_path, &["/other".to_string()]).is_none());
    }

    #[test]
    fn background_file_index_scans_and_searches() {
        let root = tempdir().unwrap();
        fs::write(root.path().join("atlas-search-probe.txt"), "probe").unwrap();
        let service = SearchService::new();
        service
            .start_file_index(
                vec![root.path().to_path_buf()],
                root.path().join("cache/index.json"),
            )
            .unwrap();

        let deadline = Instant::now() + Duration::from_secs(2);
        while service.file_status().unwrap().phase != FileIndexPhase::Ready
            && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(10));
        }
        let hits = service
            .search("atlas-search", 10, &[FILE_NAMESPACE.to_string()])
            .unwrap();
        service.stop_file_index().unwrap();

        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].document.title, "atlas-search-probe.txt");
    }

    #[test]
    fn fresh_cache_becomes_ready_without_a_full_rescan() {
        let root = tempdir().unwrap();
        let canonical_root = root.path().canonicalize().unwrap();
        let roots = vec![canonical_root.to_string_lossy().into_owned()];
        let cache_path = root.path().join("cache/index.json");
        let cached = document(
            "cached",
            FILE_NAMESPACE,
            "Cached Result.txt",
            "/cached/result.txt",
        );
        save_cache(&cache_path, &roots, vec![cached]).unwrap();
        fs::write(root.path().join("uncached-probe.txt"), "probe").unwrap();

        let service = SearchService::new();
        service
            .start_file_index(vec![canonical_root], cache_path)
            .unwrap();
        let deadline = Instant::now() + Duration::from_secs(1);
        while service.file_status().unwrap().phase != FileIndexPhase::Ready
            && Instant::now() < deadline
        {
            thread::sleep(Duration::from_millis(10));
        }

        assert_eq!(
            service.search("cached", 10, &[]).unwrap().len(),
            1,
            "fresh cache should be queryable immediately"
        );
        assert!(
            service
                .search("uncached-probe", 10, &[])
                .unwrap()
                .is_empty(),
            "fresh cache should not trigger an eager full rescan"
        );
        service.stop_file_index().unwrap();
    }

    #[test]
    fn watcher_ignores_cache_and_other_noisy_paths() {
        let index = SearchIndex::default();
        let event = Event::new(EventKind::Any).add_path(PathBuf::from(
            "/Users/test/Library/Application Support/Atlas/index.json",
        ));

        assert!(!apply_event(
            &index,
            &[PathBuf::from("/Users/test")],
            event,
            &AtomicBool::new(false)
        ));

        let root = tempdir().unwrap();
        assert!(!apply_event(
            &index,
            &[root.path().to_path_buf()],
            Event::new(EventKind::Any).add_path(root.path().to_path_buf()),
            &AtomicBool::new(false)
        ));

        let existing_directory = root.path().join("folder");
        fs::create_dir(&existing_directory).unwrap();
        assert!(!apply_event(
            &index,
            &[root.path().to_path_buf()],
            Event::new(EventKind::Any).add_path(existing_directory),
            &AtomicBool::new(false)
        ));
    }

    #[test]
    fn searches_large_catalog_without_reprocessing_documents() {
        let index = SearchIndex::default();
        let mut documents = (0..100_000)
            .map(|number| {
                document(
                    &format!("file-{number}"),
                    FILE_NAMESPACE,
                    &format!("ordinary-file-{number}.txt"),
                    "",
                )
            })
            .collect::<Vec<_>>();
        documents.push(document("needle", FILE_NAMESPACE, "Needle Project.md", ""));
        index.replace_namespace(FILE_NAMESPACE, documents).unwrap();

        let started = Instant::now();
        let hits = index.search("needle", 10, &[]).unwrap();

        assert_eq!(
            hits.first().map(|hit| hit.document.id.as_str()),
            Some("needle")
        );
        assert!(
            started.elapsed() < Duration::from_secs(1),
            "100k-candidate search took {:?}",
            started.elapsed()
        );
    }
}
