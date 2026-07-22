//! AI 指令库(Raycast AI Commands 等价):预设 prompt 模板,`{selection}`
//! 占位注入选中文本;执行走现有流式管线,这里只管 CRUD 与模板渲染。
//! 存储 `<root>/commands.json`,首次访问写入内置指令。

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::AiError;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum AiCommandOutput {
    /// 结果面板展示
    Panel,
    /// 直接粘贴替换选中文本
    Paste,
    /// 拷贝到剪贴板
    Copy,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AiCommand {
    pub id: String,
    pub name: String,
    /// SF Symbol 名(Swift 侧渲染)。
    pub icon: String,
    /// 模板,`{selection}` 处注入选中文本。
    pub prompt_template: String,
    pub output: AiCommandOutput,
    pub builtin: bool,
}

/// 渲染最终 prompt。模板无 `{selection}` 时选中文本追加末尾。
pub fn render_prompt(template: &str, selection: &str) -> String {
    if template.contains("{selection}") {
        template.replace("{selection}", selection)
    } else if selection.is_empty() {
        template.to_string()
    } else {
        format!("{template}\n\n{selection}")
    }
}

fn builtin_commands() -> Vec<AiCommand> {
    let entries: [(&str, &str, &str, &str, AiCommandOutput); 12] = [
        ("builtin-summarize", "总结要点", "list.bullet", "总结以下内容的关键要点,用简洁的中文列表:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-improve", "改写润色", "wand.and.stars", "改写并润色以下文字,保持原意,输出语言与原文一致,只输出改写结果:\n\n{selection}", AiCommandOutput::Paste),
        ("builtin-fix", "修正拼写语法", "checkmark.seal", "修正以下文字的拼写和语法错误,只输出修正后的文本:\n\n{selection}", AiCommandOutput::Paste),
        ("builtin-to-zh", "翻译成中文", "character.book.closed.zh", "把以下内容翻译成简体中文,只输出译文:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-to-en", "翻译成英文", "character.book.closed", "Translate the following into natural English. Output only the translation:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-explain-code", "解释代码", "curlybraces", "解释以下代码的作用与关键逻辑,用中文:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-comment-code", "加注释", "text.alignleft", "为以下代码添加恰当注释,保持代码不变,只输出带注释的代码:\n\n{selection}", AiCommandOutput::Paste),
        ("builtin-find-bugs", "找 Bug", "ant", "审查以下代码,列出潜在 bug 与风险点,按严重程度排序,用中文:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-write-tests", "写测试", "checklist", "为以下代码编写单元测试,沿用其语言与常见测试框架,只输出测试代码:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-extract", "提取要点", "doc.text.magnifyingglass", "从以下内容提取关键信息(人名/时间/数字/结论),用中文条目列出:\n\n{selection}", AiCommandOutput::Panel),
        ("builtin-longer", "扩写", "text.append", "在保持原意与语气的前提下扩写以下内容,输出语言与原文一致,只输出扩写结果:\n\n{selection}", AiCommandOutput::Paste),
        ("builtin-formal", "正式化", "briefcase", "把以下内容改写成正式、专业的语气,输出语言与原文一致,只输出结果:\n\n{selection}", AiCommandOutput::Paste),
    ];
    entries
        .into_iter()
        .map(|(id, name, icon, template, output)| AiCommand {
            id: id.to_string(),
            name: name.to_string(),
            icon: icon.to_string(),
            prompt_template: template.to_string(),
            output,
            builtin: true,
        })
        .collect()
}

pub struct AiCommandStore {
    path: PathBuf,
}

impl AiCommandStore {
    pub fn new(root: impl Into<PathBuf>) -> Result<Self, AiError> {
        let root = root.into();
        fs::create_dir_all(&root)?;
        Ok(Self {
            path: root.join("commands.json"),
        })
    }

    /// 首次访问播种内置指令。
    pub fn list(&self) -> Result<Vec<AiCommand>, AiError> {
        if !self.path.exists() {
            let seeded = builtin_commands();
            self.write(&seeded)?;
            return Ok(seeded);
        }
        Ok(serde_json::from_str(&fs::read_to_string(&self.path)?)?)
    }

    /// 同 id 覆盖,新 id 追加。内置指令允许改 prompt/输出方式,但 builtin 标记保留。
    pub fn save(&self, command: &AiCommand) -> Result<(), AiError> {
        let mut commands = self.list()?;
        if let Some(existing) = commands.iter_mut().find(|c| c.id == command.id) {
            let keep_builtin = existing.builtin;
            *existing = command.clone();
            existing.builtin = keep_builtin;
        } else {
            let mut fresh = command.clone();
            fresh.builtin = false;
            commands.push(fresh);
        }
        self.write(&commands)
    }

    /// 内置不可删。
    pub fn delete(&self, id: &str) -> Result<(), AiError> {
        let mut commands = self.list()?;
        let Some(index) = commands.iter().position(|c| c.id == id) else {
            return Err(AiError::NotFound(id.to_string()));
        };
        if commands[index].builtin {
            return Err(AiError::Corrupt("builtin command cannot be deleted".into()));
        }
        commands.remove(index);
        self.write(&commands)
    }

    fn write(&self, commands: &[AiCommand]) -> Result<(), AiError> {
        fs::write(&self.path, serde_json::to_string_pretty(commands)?)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> (tempfile::TempDir, AiCommandStore) {
        let dir = tempfile::tempdir().unwrap();
        let store = AiCommandStore::new(dir.path()).unwrap();
        (dir, store)
    }

    #[test]
    fn seeds_builtins_once() {
        let (_d, s) = store();
        let list = s.list().unwrap();
        assert_eq!(list.len(), 12);
        assert!(list.iter().all(|c| c.builtin));
        // 再次读取不重复播种。
        assert_eq!(s.list().unwrap().len(), 12);
    }

    #[test]
    fn save_custom_and_edit_builtin() {
        let (_d, s) = store();
        s.list().unwrap();
        let custom = AiCommand {
            id: "my-cmd".into(),
            name: "自定义".into(),
            icon: "star".into(),
            prompt_template: "做点什么: {selection}".into(),
            output: AiCommandOutput::Panel,
            builtin: true, // 伪造 builtin,save 必须清掉
        };
        s.save(&custom).unwrap();
        let list = s.list().unwrap();
        let saved = list.iter().find(|c| c.id == "my-cmd").unwrap();
        assert!(!saved.builtin);

        // 改内置 prompt,builtin 标记保留。
        let mut edited = list.iter().find(|c| c.id == "builtin-fix").unwrap().clone();
        edited.prompt_template = "新 prompt {selection}".into();
        edited.builtin = false; // 伪造也无效
        s.save(&edited).unwrap();
        let after = s.list().unwrap();
        let builtin = after.iter().find(|c| c.id == "builtin-fix").unwrap();
        assert!(builtin.builtin);
        assert_eq!(builtin.prompt_template, "新 prompt {selection}");
    }

    #[test]
    fn builtin_delete_rejected_custom_ok() {
        let (_d, s) = store();
        s.list().unwrap();
        assert!(s.delete("builtin-fix").is_err());
        let custom = AiCommand {
            id: "temp".into(),
            name: "t".into(),
            icon: "star".into(),
            prompt_template: "{selection}".into(),
            output: AiCommandOutput::Copy,
            builtin: false,
        };
        s.save(&custom).unwrap();
        s.delete("temp").unwrap();
        assert!(s.list().unwrap().iter().all(|c| c.id != "temp"));
        assert!(s.delete("missing").is_err());
    }

    #[test]
    fn render_prompt_variants() {
        assert_eq!(render_prompt("翻译: {selection}", "hi"), "翻译: hi");
        assert_eq!(render_prompt("总结", "正文"), "总结\n\n正文");
        assert_eq!(render_prompt("裸模板", ""), "裸模板");
    }
}
