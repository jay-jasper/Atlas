import SwiftUI

struct NowPlayingPanel: View {
    @ObservedObject var service: NowPlayingService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Now Playing", systemImage: "music.note")
                    .font(.headline)
                Spacer()
                Button { service.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
            }

            if service.track.hasTrack {
                Text(service.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(NowPlayingFormatter.subtitle(service.track))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2).fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(NowPlayingFormatter.progress(service.track)))
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(NowPlayingFormatter.timeLabel(service.track))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        service.togglePlayPause()
                    } label: {
                        Image(systemName: service.track.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text(service.statusMessage.isEmpty ? "Nothing playing." : service.statusMessage)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
