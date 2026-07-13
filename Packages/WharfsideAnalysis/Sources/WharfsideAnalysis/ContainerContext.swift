import Foundation

/// Container metadata attached to a digest.
public struct ContainerContext: Sendable, Equatable {
    public let containerName: String
    public let image: String
    public let exitStatus: ExitStatus
    public let restartCount: Int

    public init(containerName: String, image: String, exitStatus: ExitStatus, restartCount: Int) {
        self.containerName = containerName
        self.image = image
        self.exitStatus = exitStatus
        self.restartCount = restartCount
    }
}
