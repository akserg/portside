// WharfsideTests/ContainerLifecycleObserverTests.swift

import Foundation
import Testing
@testable import Wharfside

@Suite struct ContainerLifecycleObserverTests {
  private func summary(id: String, status: ContainerRuntimeStatus) -> ContainerSummary {
    ContainerSummary(id: id, image: "img:latest", status: status, startedAt: nil, portSummary: "—")
  }

  @Test func restartCountsRunningStoppedRunningCycle() async {
    let observer = ContainerLifecycleObserver()
    let id = "web"

    await observer.record(containers: [summary(id: id, status: .running)])
    await observer.record(containers: [summary(id: id, status: .stopped)])
    #expect(await observer.restartCount(for: id) == 0)

    await observer.record(containers: [summary(id: id, status: .running)])
    #expect(await observer.restartCount(for: id) == 1)

    await observer.record(containers: [summary(id: id, status: .stopped)])
    await observer.record(containers: [summary(id: id, status: .running)])
    #expect(await observer.restartCount(for: id) == 2)
  }

  @Test func startingStoppedContainerDoesNotCountAsRestart() async {
    let observer = ContainerLifecycleObserver()
    let id = "db"

    await observer.record(containers: [summary(id: id, status: .stopped)])
    await observer.record(containers: [summary(id: id, status: .running)])
    #expect(await observer.restartCount(for: id) == 0)
  }

  @Test func stoppingStateBehavesLikeRunningUntilStopped() async {
    let observer = ContainerLifecycleObserver()
    let id = "api"

    await observer.record(containers: [summary(id: id, status: .running)])
    await observer.record(containers: [summary(id: id, status: .stopping)])
    await observer.record(containers: [summary(id: id, status: .stopped)])
    await observer.record(containers: [summary(id: id, status: .running)])

    #expect(await observer.restartCount(for: id) == 1)
  }
}
