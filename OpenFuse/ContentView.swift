//
//  ContentView.swift
//  OpenFuse
//
//  Created by Kris Li on 8/19/25.
//

import SwiftUI
import Photos

final class CameraViewModel: ObservableObject {
    @Published var isSessionRunning = false
    @Published var statusText: String = ""

    let controller = CameraController()

    init() {
        controller.onStatus = { [weak self] s in
            DispatchQueue.main.async { self?.statusText = s }
        }
    }

    func start() {
        #if targetEnvironment(simulator)
        // Simulator has no real camera session; just show a status.
        DispatchQueue.main.async { self.statusText = "Simulator mode: ready" }
        #else
        controller.startSession()
        #endif
    }

    func stop() {
        #if targetEnvironment(simulator)
        // Nothing to stop in Simulator mode
        #else
        controller.stopSession()
        #endif
    }

    func captureJPEGOnly(burst: Int = 6) {
        #if targetEnvironment(simulator)
        controller.onStatus?("Simulator: processing test DNG burst…")
        SimulatorCapture.runBurst(outputMode: .jpegOnly, status: controller.onStatus ?? { _ in })
        #else
        controller.captureBurst(burstCount: burst, outputMode: .jpegOnly)
        #endif
    }

    func captureDNGPlusJPEG(burst: Int = 6) {
        #if targetEnvironment(simulator)
        controller.onStatus?("Simulator: processing test DNG burst…")
        SimulatorCapture.runBurst(outputMode: .dngPlusJpeg, status: controller.onStatus ?? { _ in })
        #else
        controller.captureBurst(burstCount: burst, outputMode: .dngPlusJpeg)
        #endif
    }
}

struct ContentView: View {
    @StateObject var vm = CameraViewModel()
    @State private var showHelp = false

    var body: some View {
        ZStack {
            // Preview surface: on Simulator this will be empty but we keep layout consistent
            CameraView(session: vm.controller.session)
                .overlay(alignment: .topLeading) { statusOverlay }
                .overlay(alignment: .bottom) { controls }
                .background(Color.black)
                .ignoresSafeArea()
        }
        .onAppear {
            vm.start()
            requestPhotoAddAccessIfNeeded()
        }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showHelp) { helpSheet }
    }

    // MARK: - Overlays

    private var statusOverlay: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.9))
                .frame(width: 8, height: 8)
            Text(vm.statusText.isEmpty ? "Ready" : vm.statusText)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(8)
        .background(.black.opacity(0.5))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button("JPEG‑only (clean)") { vm.captureJPEGOnly() }
                    .buttonStyle(.borderedProminent)
                Button("DNG + JPEG") { vm.captureDNGPlusJPEG() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)

            #if targetEnvironment(simulator)
            Text("Simulator mode: add test DNGs in the app bundle at TestDNGs/ to process a burst.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, 8)
            #endif

            HStack {
                Spacer()
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .tint(.white)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(.black.opacity(0.3))
    }

    // MARK: - Sheets

    private var helpSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("OpenFuse Help")
                    .font(.headline)
                Text("• **JPEG‑only**: Captures a RAW burst, aligns & averages, saves a neutral JPEG.\n• **DNG + JPEG**: Same, plus saves one DNG frame.")
                #if targetEnvironment(simulator)
                Text("**Simulator**: Add `TestDNGs/*.dng` to your app bundle. The app will load and process them since the Simulator has no real camera.")
                #else
                Text("**Device**: Grant Camera and Photos permissions when prompted.")
                #endif
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showHelp = false }
                }
            }
        }
    }

    // MARK: - Permissions

    private func requestPhotoAddAccessIfNeeded() {
        // Request lightweight add-only access so saves succeed predictably
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
    }
}

