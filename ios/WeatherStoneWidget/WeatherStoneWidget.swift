import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.a11.weatherstone.weatherstone"
private let widgetKind = "WeatherStoneWidget"
private let fallbackLocation = "현재 위치"
private let fallbackCondition = "날씨 반영 대기"
private let fallbackAccessory = "맨돌"

struct WeatherStoneEntry: TimelineEntry {
  let date: Date
  let frameIndex: Int
  let location: String
  let temperature: String
  let condition: String
  let accessory: String
  let animate: Bool
}

struct WeatherStoneProvider: TimelineProvider {
  func placeholder(in context: Context) -> WeatherStoneEntry {
    WeatherStoneEntry(
      date: Date(),
      frameIndex: 0,
      location: fallbackLocation,
      temperature: "18°C",
      condition: "살짝 흔들림",
      accessory: "맨돌",
      animate: false
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (WeatherStoneEntry) -> Void) {
    completion(loadEntry(frameIndex: 0, date: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherStoneEntry>) -> Void) {
    let defaults = UserDefaults(suiteName: widgetGroupId)
    let animate = defaults?.bool(forKey: "animate_widget") ?? false
    let frameCount = max(defaults?.integer(forKey: "frame_count") ?? 1, 1)
    let now = Date()

    let entries: [WeatherStoneEntry]
    let policy: TimelineReloadPolicy

    if animate {
      let activeFrames = min(frameCount, 4)
      entries = (0..<activeFrames).map { index in
        loadEntry(frameIndex: index, date: now.addingTimeInterval(Double(index) * 2.0))
      }
      policy = .after(now.addingTimeInterval(Double(activeFrames) * 2.0))
    } else {
      entries = [loadEntry(frameIndex: 0, date: now)]
      policy = .after(now.addingTimeInterval(15 * 60))
    }

    completion(Timeline(entries: entries, policy: policy))
  }

  private func loadEntry(frameIndex: Int, date: Date) -> WeatherStoneEntry {
    let defaults = UserDefaults(suiteName: widgetGroupId)
    return WeatherStoneEntry(
      date: date,
      frameIndex: frameIndex,
      location: defaults?.string(forKey: "location_label") ?? fallbackLocation,
      temperature: defaults?.string(forKey: "temperature_label") ?? "--",
      condition: defaults?.string(forKey: "condition_label") ?? fallbackCondition,
      accessory: defaults?.string(forKey: "accessory_label") ?? fallbackAccessory,
      animate: defaults?.bool(forKey: "animate_widget") ?? false
    )
  }
}

struct WeatherStoneWidgetView: View {
  var entry: WeatherStoneProvider.Entry

  private var imagePath: String? {
    let defaults = UserDefaults(suiteName: widgetGroupId)
    return defaults?.string(forKey: "stone_frame_\(entry.frameIndex)")
      ?? defaults?.string(forKey: "stone_image")
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color.black.opacity(0.06), Color.clear],
        startPoint: .top,
        endPoint: .bottom
      )

      VStack(spacing: 10) {
        VStack(spacing: 2) {
          Text(entry.location)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
          Text(entry.temperature)
            .font(.title3)
            .fontWeight(.heavy)
            .foregroundStyle(Color(red: 0.9, green: 0.84, blue: 0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.35), in: Capsule())

        Group {
          if let imagePath,
             let image = UIImage(contentsOfFile: imagePath) {
            Image(uiImage: image)
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .transition(.scale.combined(with: .opacity))
              .contentTransition(.opacity)
          } else {
            Text("앱을 열어 돌을 준비해 주세요")
              .font(.caption)
              .foregroundStyle(.white)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(.black.opacity(0.3), in: Capsule())
          }
        }

        VStack(spacing: 6) {
          Text(entry.condition)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.black.opacity(0.35), in: Capsule())

          Text(entry.accessory)
            .font(.caption2)
            .foregroundStyle(Color(red: 0.82, green: 0.91, blue: 0.93))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(red: 0.07, green: 0.1, blue: 0.12).opacity(0.55), in: Capsule())
        }
      }
      .padding(12)
    }
    .widgetURL(URL(string: "weatherstone://open"))
    .modifier(WidgetBackgroundModifier())
  }
}

struct WidgetBackgroundModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(.clear, for: .widget)
    } else {
      content.background(Color.clear)
    }
  }
}

@main
struct WeatherStoneWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: widgetKind, provider: WeatherStoneProvider()) { entry in
      WeatherStoneWidgetView(entry: entry)
    }
    .configurationDisplayName("날씨 알려주는 돌")
    .description("현재 날씨에 맞춰 흔들리고 바뀌는 돌 위젯")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

#Preview(as: .systemSmall) {
  WeatherStoneWidget()
} timeline: {
  WeatherStoneEntry(
    date: .now,
    frameIndex: 0,
    location: fallbackLocation,
    temperature: "18°C",
    condition: "살짝 흔들림",
    accessory: "스튜디오 헤드폰",
    animate: true
  )
}
