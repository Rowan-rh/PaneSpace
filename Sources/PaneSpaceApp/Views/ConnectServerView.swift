import SwiftUI

/// Signs in to a cloud drive: in the browser for Google Drive, with a code for Baidu Netdisk.
///
/// Both services only let registered apps in. A build can carry its own registration; otherwise
/// the user enters one once, in a section that stays folded away after it has been filled in.
struct ConnectServerView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject var cloudAccounts: CloudAccountsModel
    @Environment(\.dismiss) private var dismiss

    @State private var service: CloudService = .googleDrive
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var appFolder = ""
    @State private var showsCredentials = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to Server")
                .font(.headline)

            Picker("Service", selection: $service) {
                ForEach(CloudService.allCases) { service in
                    Text(L10n.text(service.title)).tag(service)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(cloudAccounts.connectionState.isInProgress)

            Text(L10n.text(serviceDescription))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $showsCredentials) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text(credentialsDescription))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Form {
                        TextField(L10n.text(service == .googleDrive ? "Client ID" : "AppKey"), text: $clientID)
                        SecureField(L10n.text(service == .googleDrive ? "Client secret" : "SecretKey"), text: $clientSecret)
                        if service == .baiduNetdisk {
                            TextField(L10n.text("App folder name"), text: $appFolder, prompt: Text(L10n.text("Optional")))
                        }
                    }
                    Link(destination: consoleURL) {
                        Label(L10n.text(service == .googleDrive ? "Get Google Drive API credentials" : "Open Baidu Netdisk Open Platform"), systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                .padding(.top, 6)
            } label: {
                Text(L10n.text(cloudAccounts.hasBundledCredentials(for: service) ? "Use your own app credentials" : "App credentials"))
            }
            .disabled(cloudAccounts.connectionState.isInProgress)

            statusView

            HStack {
                Spacer()
                Button("Cancel") {
                    cloudAccounts.cancelConnection()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Connect") { connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConnect)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { loadCredentials() }
        .onChange(of: service) {
            cloudAccounts.dismissConnectionError()
            loadCredentials()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch cloudAccounts.connectionState {
        case .idle:
            EmptyView()
        case .waitingForBrowser:
            progressRow("Continue signing in in your browser.")
        case let .waitingForDeviceApproval(code):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    if let qrCodeURL = code.qrCodeURL {
                        AsyncImage(url: qrCodeURL) { image in
                            image.resizable().interpolation(.none).scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 120, height: 120)
                        .accessibilityLabel(Text("Authorization QR code"))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan the code with the Baidu Netdisk app, or enter this code on Baidu's authorization page:")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(code.userCode)
                            .font(.title2.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Button("Open Authorization Page") {
                            NSWorkspace.shared.open(code.verificationURL)
                        }
                    }
                }
                progressRow("Waiting for approval…")
            }
        case .finishing:
            progressRow("Finishing…")
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.text(message))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var serviceDescription: String {
        switch service {
        case .googleDrive:
            "Sign in with your Google account to browse My Drive in Google Drive."
        case .baiduNetdisk:
            "Sign in with your Baidu account to browse Baidu Netdisk. Baidu only lets apps reach the folders it grants them, normally “My App Data/<app name>”."
        }
    }

    private var credentialsDescription: String {
        switch service {
        case .googleDrive:
            "Google only lets registered apps read Google Drive. Register one once in Google's developer console: enable the Google Drive API and create an OAuth client of type “Desktop app”."
        case .baiduNetdisk:
            "Baidu only lets registered apps read Baidu Netdisk. Register one once on the Baidu Netdisk open platform and enter its AppKey and SecretKey."
        }
    }

    private var consoleURL: URL {
        switch service {
        case .googleDrive: URL(string: "https://console.cloud.google.com/apis/library/drive.googleapis.com")!
        case .baiduNetdisk: URL(string: "https://pan.baidu.com/union/console")!
        }
    }

    private var canConnect: Bool {
        !cloudAccounts.connectionState.isInProgress &&
            (CloudAppCredentials(clientID: clientID, clientSecret: clientSecret).isComplete ||
                cloudAccounts.hasBundledCredentials(for: service))
    }

    private func loadCredentials() {
        let saved = cloudAccounts.savedAppCredentials(for: service)
        clientID = saved?.clientID ?? ""
        clientSecret = saved?.clientSecret ?? ""
        appFolder = saved?.appFolder ?? ""
        // Only someone who still has to enter credentials needs to see the fields.
        showsCredentials = saved?.isComplete != true && !cloudAccounts.hasBundledCredentials(for: service)
    }

    private func connect() {
        let credentials = CloudAppCredentials(
            clientID: clientID,
            clientSecret: clientSecret,
            appFolder: service == .baiduNetdisk ? appFolder : nil
        )
        cloudAccounts.connect(service, credentials: credentials) { account in
            appModel.open(account.homeURL)
            dismiss()
        }
    }
}
