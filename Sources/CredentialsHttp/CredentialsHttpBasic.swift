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
import LoggerAPI
import Credentials

import SwiftyJSON

import Foundation

public class CredentialsHttpBasic : CredentialsPluginProtocol {
    
    public var name : String {
        return "HttpBasic"
    }
    
    public var redirecting: Bool {
        return false
    }

#if os(OSX)
    public var usersCache : NSCache<NSString, BaseCacheElement>?
#else
    public var usersCache : NSCache?
#endif

    private var verifyCallback : (String, String?, ((UserProfile?, String?) -> Void)) -> Void
    
    public var realm = "Users"
    
    public init (verify: (String, String?, ((UserProfile?, String?) -> Void)) -> Void, realm: String?=nil) {
        verifyCallback = verify
        if let realm = realm {
            self.realm = realm
        }
    }
    
    public func authenticate (request: RouterRequest, response: RouterResponse, options: [String:OptionValue],                            onSuccess: (UserProfile) -> Void, onFailure: (HTTPStatusCode?, [String:String]?) -> Void, onPass: (HTTPStatusCode?, [String:String]?) -> Void, inProgress: () -> Void)  {
        
        var authorization : String
        if let userinfo = request.params["userinfo"] {
            authorization = userinfo
        }
        else {
            guard request.headers["Authorization"] != nil,
                let authorizationHeader = request.headers["Authorization"] where
                authorizationHeader.bridge().components(separatedBy: " ")[0] == "Basic",
                let decodedData = NSData(base64Encoded: authorizationHeader.bridge().components(separatedBy: " ")[1], options:NSDataBase64DecodingOptions(rawValue: 0)),
                let userAuthorization = NSString(data: decodedData, encoding: NSUTF8StringEncoding) else {
                onPass(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
                return
            }

            authorization = userAuthorization as String
        }
        
        // bridge????
        let credentials = authorization.bridge().components(separatedBy: ":")
        guard credentials.count >= 2 else {
            onFailure(.badRequest, nil)
            return
        }
        
        // Is it possible there is some unrelated userinfo and also Authorization header????
        
        let userid = credentials[0]
        let password = credentials[1]        
                
        let cacheElement = usersCache!.object(forKey: (userid+password).bridge()) // bridge???
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

        
        verifyCallback(userid, password) { userProfile, _ in // error???
            if let userProfile = userProfile {
                onSuccess(userProfile)
            }
            else {
                onFailure(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"" + self.realm + "\""])
            }
        }
    }
}
