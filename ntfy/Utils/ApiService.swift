import Foundation

class ApiService {
    static let shared = ApiService()
    static let userAgent = "ntfy/\(Config.version) (build \(Config.build); iOS \(Config.osVersion))"
    
    private let tag = "ApiService"
    
    func poll(subscription: Subscription, user: BasicUser?, completionHandler: @escaping ([Message]?, Error?) -> Void) {
        guard let url = URL(string: subscription.urlString()) else {
            // FIXME
            return
        }
        let since = subscription.lastNotificationId ?? "all"
        let urlString = "\(url)/json?poll=1&since=\(since)"
        
        Log.d(tag, "Polling from \(urlString) with user \(user?.username ?? "anonymous")")
        fetchJsonData(urlString: urlString, user: user, completionHandler: completionHandler)
    }
    
    func poll(subscription: Subscription, messageId: String, user: BasicUser?, completionHandler: @escaping (Message?, Error?) -> Void) {
        let url = URL(string: "\(subscription.urlString())/json?poll=1&id=\(messageId)")!
        Log.d(tag, "Polling single message from \(url) with user \(user?.username ?? "anonymous")")
        
        let request = newRequest(url: url, user: user)
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completionHandler(nil, error)
                return
            }
            do {
                let message = try JSONDecoder().decode(Message.self, from: data!)
                completionHandler(message, nil)
            } catch {
                completionHandler(nil, error)
            }
        }.resume()
    }

    func publish(
        subscription: Subscription,
        user: BasicUser?,
        message: String,
        title: String,
        priority: Int = 3,
        tags: [String] = []
    ) {
        guard let url = URL(string: subscription.urlString()) else { return }
        var request = newRequest(url: url, user: user)

        Log.d(tag, "Publishing to \(url)")
        
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        request.setValue(String(priority), forHTTPHeaderField: "Priority")
        request.setValue(tags.joined(separator: ","), forHTTPHeaderField: "Tags")
        request.httpBody = message.data(using: String.Encoding.utf8)
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            guard error == nil else {
                Log.e(self.tag, "Error publishing message", error!)
                return
            }
            Log.d(self.tag, "Publishing message succeeded", response)
        }.resume()
    }
    
    func checkAuth(baseUrl: String, topic: String, user: BasicUser?, completionHandler: @escaping(AuthCheckResponse?, Error?) -> Void) {
        guard let url = URL(string: topicAuthUrl(baseUrl: baseUrl, topic: topic)) else { return }
        let request = newRequest(url: url, user: user)
        Log.d(tag, "Checking auth for \(url) with user \(user?.username ?? "anonymous")")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                Log.e(self.tag, "Error checking auth: \(error)")
                completionHandler(nil, error)
            }
            if let data = data {
                do {
                    let result = try JSONDecoder().decode(AuthCheckResponse.self, from: data)
                    Log.d(self.tag, "Auth result: \(result)")
                    completionHandler(result, nil)
                } catch {
                    Log.e(self.tag, "Error handling auth response: \(error)")
                    completionHandler(nil, error)
                }
            }
        }.resume()
    }

    private func fetchJsonData<T: Decodable>(urlString: String, user: BasicUser?, completionHandler: @escaping ([T]?, Error?) -> ()) {
        guard let url = URL(string: urlString) else { return }
        let request = newRequest(url: url, user: user)
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                Log.e(self.tag, "Error fetching data", error)
                completionHandler(nil, error)
                return
            }
            do {
                let lines = String(decoding: data!, as: UTF8.self).split(whereSeparator: \.isNewline)
                var notifications: [T] = []
                for jsonLine in lines {
                    notifications.append(try JSONDecoder().decode(T.self, from: jsonLine.data(using: .utf8)!))
                }
                completionHandler(notifications, nil)
            } catch {
                Log.e(self.tag, "Error fetching data", error)
                completionHandler(nil, error)
            }
        }.resume()
    }
    
    private func newRequest(url: URL, user: BasicUser?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(ApiService.userAgent, forHTTPHeaderField: "User-Agent")
        if let user = user {
            request.setValue(user.toHeader(), forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

struct BasicUser {
    let username: String
    let password: String
    
    func toHeader() -> String {
        return "Basic " + String(format: "%@:%@", username, password).data(using: String.Encoding.utf8)!.base64EncodedString()
    }
}

struct AuthCheckResponse: Codable {
    let success: Bool?
    let code: Int?
    let http: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, code, http, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.success = try container.decodeIfPresent(Bool.self, forKey: .success)
        self.code = try container.decodeIfPresent(Int.self, forKey: .code)
        self.http = try container.decodeIfPresent(Int.self, forKey: .http)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}
