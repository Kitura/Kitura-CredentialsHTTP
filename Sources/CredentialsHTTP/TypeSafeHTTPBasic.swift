/**
 * Copyright IBM Corporation 2018
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Kitura
import KituraNet
import Credentials

import Foundation

/**
 A `TypeSafeCredentials` plugin for HTTP basic authentication.
 This protocol will be implemented by a Swift object defined by the user.
 The plugin must implement a `verifyPassword` function which takes a username and password as input
 and returns an instance of `Self` on success or `nil` on failure.
 This instance must contain the authentication `provider` (defaults to "HTTPBasic") and an `id`, uniquely identifying the user.
 The users object can then be used in TypeSafeMiddlware routes to authenticate with HTTP basic.
 ### Usage Example: ###
 ```swift
 public struct MyHTTPBasic: TypeSafeHTTPBasic {
 
    public var id: String
 
    static let users = ["John" : "12345", "Mary" : "qwerasdf"]
 
    public static let realm = "Login message"
 
    public static func verifyPassword(username: String, password: String, callback: @escaping (TestHTTPBasic?) -> Void) {
        if let storedPassword = users[username], storedPassword == password {
            callback(TestHTTPBasic(id: username))
        } else {
            callback(nil)
        }
    }
 }
 
 struct User: Codable {
    let name: String
 }
 
 router.get("/authedFruits") { (authedUser: MyHTTPBasic, respondWith: (User?, RequestError?) -> Void) in
    let user = User(name: authedUser.id)
    respondWith(user, nil)
 }
 ```
 */
public protocol TypeSafeHTTPBasic : TypeSafeCredentials {
    
    /// The realm for which these credentials are valid (defaults to "User")
    static var realm: String { get }
    
    /// The function that takes a username, a password and a callback which accepts a TypeSafeHTTPBasic instance on success or nil on failure.
    static func verifyPassword(username: String, password: String, callback: @escaping (Self?) -> Void) -> Void
    
}

extension TypeSafeHTTPBasic {
    
    /// The name of the authentication provider (defaults to "HTTPBasic")
    public var provider: String {
        return "HTTPBasic"
    }
    
    /// The realm for which these credentials are valid (defaults to "User")
    public static var realm: String {
        return "User"
    }
    
    /// Authenticate incoming request using HTTP Basic authentication.
    ///
    /// - Parameter request: The `RouterRequest` object used to get information
    ///                     about the request.
    /// - Parameter response: The `RouterResponse` object used to respond to the
    ///                       request.
    /// - Parameter onSuccess: The closure to invoke in the case of successful authentication.
    /// - Parameter onFailure: The closure to invoke in the case of an authentication failure.
    /// - Parameter onSkip: The closure to invoke when the plugin doesn't recognize the
    ///                     authentication data in the request.
    public static func authenticate(request: RouterRequest, response: RouterResponse, onSuccess: @escaping (Self) -> Void, onFailure: @escaping (HTTPStatusCode?, [String : String]?) -> Void, onSkip: @escaping (HTTPStatusCode?, [String : String]?) -> Void) {
        
        let userid: String
        let password: String
        if let requestUser = request.urlURL.user, let requestPassword = request.urlURL.password {
            userid = requestUser
            password = requestPassword
        } else {
            guard let authorizationHeader = request.headers["Authorization"]  else {
                return onSkip(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + realm + "\""])
            }
            
            let authorizationHeaderComponents = authorizationHeader.components(separatedBy: " ")
            guard authorizationHeaderComponents.count == 2,
                authorizationHeaderComponents[0] == "Basic",
                let decodedData = Data(base64Encoded: authorizationHeaderComponents[1], options: Data.Base64DecodingOptions(rawValue: 0)),
                let userAuthorization = String(data: decodedData, encoding: .utf8) else {
                    return onSkip(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + realm + "\""])
            }
            let credentials = userAuthorization.components(separatedBy: ":")
            guard credentials.count >= 2 else {
                return onFailure(.badRequest, nil)
            }
            userid = credentials[0]
            password = credentials[1]
        }
        
        verifyPassword(username: userid, password: password) { selfInstance in
            if let selfInstance = selfInstance {
                onSuccess(selfInstance)
            } else {
                onFailure(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
            }
        }
    }
}
