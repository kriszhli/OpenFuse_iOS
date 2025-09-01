import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vm: CameraViewModel
    @State private var showSavedBanner: Bool = false

    var body: some View {
        ZStack {
            // Live camera feed (device) or placeholder (simulator)
            #if targetEnvironment(simulator)
            Color.black
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "camera.slash")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Camera not available in Simulator")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                )
            #else
            CameraPreview(session: vm.session)
                .ignoresSafeArea()
            #endif

            // Loading overlay
            if vm.isConfiguring {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    )
            }

            // Top saved banner (moved down to avoid Dynamic Island / notch)
            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top
                VStack {
                    if showSavedBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.white)
                            Text("Saved to Photos")
                                .foregroundStyle(.white)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.7), in: Capsule())
                        // Place below safe-area plus extra spacing to clear the Island
                        .padding(.top, topInset + 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: showSavedBanner)
                    }
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
            }

            // Bottom bar
            VStack {
                Spacer()
                HStack(spacing: 24) {
                    // Flash toggle (simple on/off for photo capture)
                    Button {
                        vm.toggleFlash()
                    } label: {
                        Image(systemName: vm.isFlashOn ? "bolt.fill" : "bolt.slash")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .disabled(vm.isConfiguring || !vm.supportsCamera)

                    // Shutter
                    Button {
                        Task { await vm.capturePhoto() }
                    } label: {
                        ZStack {
                            Circle().fill(.white.opacity(0.25)).frame(width: 84, height: 84)
                            Circle().fill(.white).frame(width: 68, height: 68)
                        }
                    }
                    .disabled(vm.isConfiguring || !vm.supportsCamera)
                    .accessibilityLabel("Capture Photo")

                    // Flip camera
                    Button {
                        Task { await vm.flipCamera() }
                    } label: {
                        Image(systemName: "camera.rotate")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .disabled(vm.isConfiguring || !vm.supportsCamera)
                }
                .padding(.bottom, 32)
            }
        }
        .task {
            // Configure on appear
            await vm.configure()
        }
        // Auto-show and dismiss banner when didSave toggles true
        .onChange(of: vm.didSave) { _, newValue in
            guard newValue else { return }
            withAnimation {
                showSavedBanner = true
            }
            // Auto-hide after a short delay and reset vm.didSave
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_250_000_000) // ~1.25s
                withAnimation {
                    showSavedBanner = false
                }
                vm.didSave = false
            }
        }
        // Permission alert (still interactive)
        .alert("Permission Needed", isPresented: $vm.showPermissionAlert) {
            Button("Open Settings") { vm.openSettings() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please allow Camera and Photo Library (Add) access.")
        }
        // Error alert (still interactive)
        .alert(
            "Error",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if $0 == false { vm.errorMessage = nil } }
            )
        ) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            if let errorMessage = vm.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CameraViewModel())
}
