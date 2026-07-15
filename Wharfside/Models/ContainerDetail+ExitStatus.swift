// Models/ContainerDetail+ExitStatus.swift

import Foundation
import WharfsideAnalysis

extension ContainerDetail {
    nonisolated func replacingExitStatus(_ exitStatus: ExitStatus) -> ContainerDetail {
        ContainerDetail(
            id: id,
            image: image,
            status: status,
            command: command,
            createdAt: createdAt,
            startedAt: startedAt,
            exitStatus: exitStatus,
            restartCount: restartCount,
            ports: ports,
            mounts: mounts,
            environment: environment,
            networks: networks
        )
    }
}
