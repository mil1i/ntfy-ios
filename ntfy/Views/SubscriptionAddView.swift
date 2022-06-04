import SwiftUI

struct SubscriptionAddView: View {
    private let tag = "SubscriptionAddView"
    
    @Binding var isShowing: Bool
    
    @EnvironmentObject private var store: Store
    @State private var topic: String = ""
    @State private var useAnother: Bool = false
    @State private var baseUrl: String = ""
    
    @State private var showLogin: Bool = false
    @State private var username: String = ""
    @State private var password: String = ""

    private var subscriptionManager: SubscriptionManager {
        return SubscriptionManager(store: store)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(
                    footer:
                        Text("Topics are not password protected, so choose a name that's not easy to guess. Once subscribed, you can PUT/POST notifications")
                ) {
                    TextField("Topic name, e.g. phil_alerts", text: $topic)
                        .disableAutocapitalization()
                        .disableAutocorrection(true)
                }
                Section(
                    footer:
                        (useAnother) ? Text("Support for self-hosted servers is currently limited. To ensure instant delivery, be sure to set upstream-base-url in your server's config, otherwise messages may arrive with significant delay. Auth is not yet supported.") : Text("")
                ) {
                    Toggle("Use another server", isOn: $useAnother)
                    if useAnother {
                        TextField("Server URL, e.g. https://ntfy.example.com", text: $baseUrl)
                            .disableAutocapitalization()
                            .disableAutocorrection(true)
                    }
                }
            }
            .navigationTitle("Add subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: cancelAction) {
                        Text("Cancel")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: subscribeOrShowLoginAction) {
                        Text("Subscribe")
                    }
                    .disabled(!isValid())
                }
            }
            .background(Group {
                NavigationLink(
                    destination: loginView,
                    isActive: $showLogin
                ) {
                    EmptyView()
                }
            })
        }
    }
    
    private var loginView: some View {
        Form {
            Section(
                footer:
                    Text("This topic requires that you login with username and password. The user will be stored on your device, and will be re-used for other topics.")
            ) {
                TextField("Username", text: $username)
                    .disableAutocapitalization()
                    .disableAutocorrection(true)
                TextField("Password", text: $password)
                    .disableAutocapitalization()
                    .disableAutocorrection(true)
            }
        }
        .navigationTitle("Login required")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: subscribeWithUserAction) {
                    Text("Subscribe")
                }
                .disabled(!isValid())
            }
        }
    }
    
    private var sanitizedTopic: String {
        return topic.trimmingCharacters(in: .whitespaces)
    }
    
    private func isValid() -> Bool {
        if sanitizedTopic.isEmpty {
            return false
        } else if sanitizedTopic.range(of: "^[-_A-Za-z0-9]{1,64}$", options: .regularExpression, range: nil, locale: nil) == nil {
            return false
        } else if store.getSubscription(baseUrl: selectedBaseUrl, topic: topic) != nil {
            return false
        }
        return true
    }
    
    private func subscribeOrShowLoginAction() {
        let user = store.getUser(baseUrl: selectedBaseUrl)?.toBasicUser()
        ApiService.shared.checkAuth(baseUrl: selectedBaseUrl, topic: topic, user: user) { (response, error) in
            if response?.success == true {
                DispatchQueue.global(qos: .background).async {
                    subscriptionManager.subscribe(baseUrl: selectedBaseUrl, topic: sanitizedTopic)
                }
                isShowing = false
            } else {
                showLogin = true
            }
        }
    }
    
    private func subscribeWithUserAction() {
        let user = BasicUser(username: username, password: password)
        ApiService.shared.checkAuth(baseUrl: selectedBaseUrl, topic: topic, user: user) { (response, error) in
            if response?.success == true {
                DispatchQueue.global(qos: .background).async {
                    store.save(userBaseUrl: selectedBaseUrl, username: username, password: password)
                    subscriptionManager.subscribe(baseUrl: selectedBaseUrl, topic: sanitizedTopic)
                }
                isShowing = false
            } else {
                showLogin = true
            }
        }
    }
    
    private func cancelAction() {
        isShowing = false
    }
    
    private var selectedBaseUrl: String {
        return (useAnother) ? baseUrl : Config.appBaseUrl
    }
}

struct SubscriptionAddView_Previews: PreviewProvider {
    @State static var isShowing = true
    
    static var previews: some View {
        let store = Store.preview
        SubscriptionAddView(isShowing: $isShowing)
            .environmentObject(store)
    }
}
