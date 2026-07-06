import Foundation

/// Container metadata attached to a digest.
public struct ContainerContext: Sendable, Equatable {
    public let containerName: String
    public let image: String
    public let exitCode: Int32?
    public let restartCount: Int

    public init(containerName: String, image: String, exitCode: Int32?, restartCount: Int) {
        self.containerName = containerName
        self.image = image
        self.exitCode = exitCode
        self.restartCount = restartCount
    }
}
