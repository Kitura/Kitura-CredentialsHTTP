/**
 * Copyright IBM Corporation 2016
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

// MARK CredentialsHTTPBasic

/// Authenticate requests using HTTP Basic authentication.
/// See [RFC 7617](https://tools.ietf.org/html/rfc7617) for details.
public class CredentialsHTTPBasic : CredentialsPluginProtocol {
    
    /// The name of the plugin.
    public var name: String {
        return "HTTPBasic"
    }
    
    /// An indication as to whether the plugin is redirecting or not.
    public var redirecting: Bool {
        return false
    }

    /// User profile cache.
    public var usersCache: NSCache<NSString, BaseCacheElement>?
    
    private var userProfileLoader: UserProfileLoader? = nil

    private var verifyPassword: VerifyPassword? = nil

    /// The authentication realm attribute.
    public var realm: String
    
    /// Initialize a `CredentialsHTTPBasic` instance.
    ///
    /// - Parameter userProfileLoader: The callback for loading the user profile.
    /// - Parameter realm: The realm attribute.
    @available(*, deprecated: 2.0, message: "userProfileLoader has been deprecated from Basic Authentication because of security improvements. Please use verifyPassword.")  public init (userProfileLoader: @escaping UserProfileLoader, realm: String?=nil) {
        self.userProfileLoader = userProfileLoader
        self.realm = realm ?? "Users"
    }

    /// Initialize a `CredentialsHTTPBasic` instance.
    ///
    /// - Parameter verifyPassword: The callback for verifying the password of the user.
    /// - Parameter realm: The realm attribute.
    public init (verifyPassword: @escaping VerifyPassword, realm: String?=nil) {
        self.verifyPassword = verifyPassword
        self.realm = realm ?? "Users"
    }

    /// Authenticate incoming request using HTTP Basic authentication.
    ///
    /// - Parameter request: The `RouterRequest` object used to get information
    ///                     about the request.
    /// - Parameter response: The `RouterResponse` object used to respond to the
    ///                       request.
    /// - Parameter options: The dictionary of plugin specific options.
    /// - Parameter onSuccess: The closure to invoke in the case of successful authentication.
    /// - Parameter onFailure: The closure to invoke in the case of an authentication failure.
    /// - Parameter onPass: The closure to invoke when the plugin doesn't recognize the
    ///                     authentication data in the request.
    /// - Parameter inProgress: The closure to invoke to cause a redirect to the login page in the
    ///                     case of redirecting authentication.
    public func authenticate (request: RouterRequest, response: RouterResponse,
                              options: [String:Any], onSuccess: @escaping (UserProfile) -> Void,
                              onFailure: @escaping (HTTPStatusCode?, [String:String]?) -> Void,
                              onPass: @escaping (HTTPStatusCode?, [String:String]?) -> Void,
                              inProgress: @escaping () -> Void)  {
        
        var authorization : String
        if let user = request.urlURL.user, let password = request.urlURL.password {
            authorization = user + ":" + password
        }
        else {
            let options = Data.Base64DecodingOptions(rawValue: 0)
            
            guard let authorizationHeader = request.headers["Authorization"]  else {
                onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                return
            }

            let authorizationHeaderComponents = authorizationHeader.components(separatedBy: " ")
            guard authorizationHeaderComponents.count == 2,
                authorizationHeaderComponents[0] == "Basic",
                let decodedData = Data(base64Encoded: authorizationHeaderComponents[1], options: options),
                let userAuthorization = String(data: decodedData, encoding: .utf8) else {
                    onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                    return
            }
            
            authorization = userAuthorization as String
        }
        
        let credentials = authorization.split(separator: ":", maxSplits: 1)
        guard credentials.count == 2 else {
            onFailure(.badRequest, nil)
            return
        }
        
        let userid = String(credentials[0])
        let password = String(credentials[1])
        
        if let userProfileLoader = self.userProfileLoader {
            userProfileLoader(userid) { userProfile, storedPassword in
                if let userProfile = userProfile, let storedPassword = storedPassword, storedPassword == password {
                    onSuccess(userProfile)
                }
                else {
                    onFailure(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                }
            }
        }
        else if let verifyPassword = self.verifyPassword {
            verifyPassword(userid, password) { userProfile in
                if let userProfile = userProfile {
                    onSuccess(userProfile)
                }
                else {
                    onFailure(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                }
            }
        }
        else {
            // either verifyPassword or userProfileLoader must be valid
            onFailure(.internalServerError, ["WWW-Authenticate" : "Internal server error"])
        }
    }
}
