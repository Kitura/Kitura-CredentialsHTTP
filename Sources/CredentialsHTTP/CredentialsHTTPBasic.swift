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

public class CredentialsHTTPBasic : CredentialsPluginProtocol {
    
    public var name : String {
        return "HTTPBasic"
    }
    
    public var redirecting: Bool {
        return false
    }
    
    #if os(OSX)
    public var usersCache : Cache<NSString, BaseCacheElement>?
    #else
    public var usersCache : NSCache?
    #endif
    
    private var userProfileLoader : UserProfileLoader
    
    public var realm : String
    
    public init (userProfileLoader: UserProfileLoader, realm: String?=nil) {
        self.userProfileLoader = userProfileLoader
        self.realm = realm ?? "Users"
    }
    
    public func authenticate (request: RouterRequest, response: RouterResponse, options: [String:OptionValue], onSuccess: (UserProfile) -> Void, onFailure: (HTTPStatusCode?, [String:String]?) -> Void, onPass: (HTTPStatusCode?, [String:String]?) -> Void, inProgress: () -> Void)  {
        
        var authorization : String
        if let userinfo = request.parsedURL.userinfo {
            authorization = userinfo
        }
        else {
            #if os(Linux)
                let options = NSDataBase64DecodingOptions(rawValue: 0)
            #else
                let options = NSData.Base64DecodingOptions(rawValue: 0)
            #endif
            guard request.headers["Authorization"] != nil,
                let authorizationHeader = request.headers["Authorization"] where
                authorizationHeader.components(separatedBy: " ")[0] == "Basic",
                let decodedData = NSData(base64Encoded: authorizationHeader.components(separatedBy: " ")[1], options: options) else {
                    onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                    return
            }

            #if os(Linux)
                guard let userAuthorization = String(data: decodedData, encoding: NSUTF8StringEncoding) else {
                    onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                    return
                }
            #else
                guard let userAuthorization = String(data: decodedData as Data, encoding: String.Encoding.utf8) else {
                    onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                    return
                }
            #endif
            
            authorization = userAuthorization as String
        }
        
        let credentials = authorization.components(separatedBy: ":")
        guard credentials.count >= 2 else {
            onFailure(.badRequest, nil)
            return
        }
        
        let userid = credentials[0]
        let password = credentials[1]
        
        let cacheElement = usersCache!.object(forKey: (userid+password).bridge())
        #if os(Linux)
            if let cached = cacheElement as? BaseCacheElement {
                onSuccess(cached.userProfile)
                return
            }
        #else
            if let cached = cacheElement {
                onSuccess(cached.userProfile)
                return
            }
        #endif
        
        
        userProfileLoader(userId: userid) { userProfile, storedPassword in
            if let userProfile = userProfile, let storedPassword = storedPassword where storedPassword == password {
                let newCacheElement = BaseCacheElement(profile: userProfile)
                self.usersCache!.setObject(newCacheElement, forKey: (userid+password).bridge())
                onSuccess(userProfile)
            }
            else {
                onFailure(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
            }
        }
    }
}
