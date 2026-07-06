import Foundation
import WharfsideAnalysis

@main
struct DigestPreview {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fputs("Usage: digest-preview <fixture-path> [container-name] [image]\n", stderr)
            exit(1)
        }

        let path = arguments[1]
        let containerName = arguments.count > 2 ? arguments[2] : "preview"
        let image = arguments.count > 3 ? arguments[3] : "unknown:latest"

        do {
            let text = try String(contentsOfFile: path, encoding: .utf8)
            let digest = LogDigestBuilder().build(
                logText: text,
                context: ContainerContext(
                    containerName: containerName,
                    image: image,
                    exitCode: 1,
                    restartCount: 0
                ),
                window: DigestWindow(description: "full fixture log")
            )
            let rendered = PromptRenderer().render(digest)
            print(rendered)
            fputs("\n--- estimated tokens: \(digest.estimatedTokens) ---\n", stderr)
        } catch {
            fputs("digest-preview: \(error)\n", stderr)
            exit(1)
        }
    }
}
