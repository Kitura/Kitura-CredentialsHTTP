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
import Cryptor
import LoggerAPI

import Foundation

// MARK CredentialsHTTPDigest

/// Authenticate requests using HTTP Digest authentication. 
/// See [RFC 7616](https://tools.ietf.org/html/rfc7616) for details.
public class CredentialsHTTPDigest : CredentialsPluginProtocol {
    
    /// The name of the plugin.
    public var name: String {
        return "HTTPDigest"
    }
    
    /// An indication as to whether the plugin is redirecting or not.
    public var redirecting: Bool {
        return false
    }
    
    /// User profile cache.
    public var usersCache: NSCache<NSString, BaseCacheElement>?
    
    private var userProfileLoader: UserProfileLoader
    
    /// The authentication realm attribute.
    public var realm: String
    
    /// The opaque value (optional).
    public var opaque: String?
    
    private let qop = "auth"
    
    private let algorithm = "MD5"
    
    private static let regularExpressions = RegularExpressions()
    
    /// Initialize a `CredentialsHTTPDigest` instance.
    ///
    /// - Parameter userProfileLoader: The callback for loading the user profile.
    /// - Parameter realm: The opaque value.
    /// - Parameter realm: The realm attribute.
    public init (userProfileLoader: @escaping UserProfileLoader, opaque: String?=nil, realm: String?=nil) {
        self.userProfileLoader = userProfileLoader
        self.opaque = opaque ?? nil
        self.realm = realm ?? "Users"
    }
    
    /// Authenticate incoming request using HTTP Digest authentication.
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
        
        guard request.headers["Authorization"] != nil, let authorizationHeader = request.headers["Authorization"], authorizationHeader.hasPrefix("Digest") else {
            onPass(.unauthorized, createHeaders())
            return
        }
        
        guard let credentials = CredentialsHTTPDigest.parse(params: String(authorizationHeader.characters.dropFirst(7))), credentials.count > 0,
            let userid = credentials["username"],
            let credentialsRealm = credentials["realm"], credentialsRealm == realm,
            let credentialsURI = credentials["uri"],
            credentialsURI == CredentialsHTTPDigest.reassembleURI(request.urlURL),
            let credentialsNonce = credentials["nonce"],
            let credentialsCNonce = credentials["cnonce"],
            let credentialsNC = credentials["nc"],
            let credentialsQoP = credentials["qop"], credentialsQoP == qop,
            let credentialsResponse = credentials["response"] else {
                onFailure(.badRequest, nil)
                return
        }
        
        if let opaque = opaque {
            guard let credentialsOpaque = credentials["opaque"], credentialsOpaque == opaque else {
                onFailure(.badRequest, nil)
                return
            }
        }
        
        if let credentialsAlgorithm = credentials["algorithm"] {
            guard credentialsAlgorithm == algorithm else {
                onFailure(.badRequest, nil)
                return
            }
        }
        
        userProfileLoader(userid) { userProfile, password in
            guard let userProfile = userProfile, let password = password else {
                onFailure(.unauthorized, self.createHeaders())
                return
            }
            
            let s1 = userid + ":" + credentialsRealm + ":" + password
            let ha1 = s1.digest(using: .md5)
            
            let s2 = request.method.rawValue + ":" + credentialsURI
            let ha2 = s2.digest(using: .md5)
            
            let s3 = ha1 + ":" + credentialsNonce + ":" + credentialsNC + ":" + credentialsCNonce + ":" + credentialsQoP + ":" + ha2
            let response = s3.digest(using: .md5)
            
            if response == credentialsResponse {
                onSuccess(userProfile)
            }
            else {
                onFailure(.unauthorized, self.createHeaders())
            }
        }
    }
    
    private func createHeaders () -> [String:String]? {
        var header = "Digest realm=\"" + realm + "\", nonce=\"" + CredentialsHTTPDigest.generateNonce() + "\""
        if let opaque = opaque {
            header += ", opaque=\"" + opaque + "\""
        }
        header += ", algorithm=\"" + algorithm + "\", qop=\"" + qop + "\""
        return ["WWW-Authenticate":header]
    }
    
    private static func generateNonce() -> String {
        let nonce : [UInt8]
        do {
            nonce = try Random.generate(byteCount: 16)
            return CryptoUtils.hexString(from: nonce)
        }
        catch {
            return "0a0b0c0d0e0f1a1b1c1d1e1f01234567"
        }
    }
    
    #if os(Linux)
        typealias RegularExpressionType = RegularExpression
    #else
        typealias RegularExpressionType = NSRegularExpression
    #endif
    
    private struct RegularExpressions {
        let parseRegex: RegularExpressionType
        let splitRegex: RegularExpressionType
        
        init() {
            do {
                parseRegex = try RegularExpressionType(pattern: "(\\w+)=[\"]?([^\"]+)[\"]?$", options: [])
                splitRegex = try RegularExpressionType(pattern: ",(?=(?:[^\"]|\"[^\"]*\")*$)", options: [])
            }
            catch {
                Log.error("Failed to create regular expressions used to parse Digest Authorization header")
                exit(1)
            }
        }
    }
    
    private static func parse (params: String) -> [String:String]? {
        guard let tokens = split(originalString: params) else {
            return nil
        }
        
        var result = [String:String]()
        for token in tokens {
            let nsString = NSString(string: token)
            let matches = regularExpressions.parseRegex.matches(in: token, options: [], range: NSMakeRange(0, nsString.length))
            if matches.count == 1 {
                #if os(Linux)
                    let matchOne = matches[0].range(at: 1)
                    let matchTwo = matches[0].range(at: 2)
                #else
                    let matchOne = matches[0].rangeAt(1)
                    let matchTwo = matches[0].rangeAt(2)
                #endif
                if matchOne.location != NSNotFound && matchTwo.location != NSNotFound {
                    result[nsString.substring(with: matchOne)] = nsString.substring(with: matchTwo)
                }
            }
        }
        return result
    }
    
    private static func split(originalString: String) -> [String]? {
        var result = [String]()
        let nsString = NSString(string: originalString)
        var start = 0
        while true {
            let results = regularExpressions.splitRegex.rangeOfFirstMatch(in: originalString, options: [], range: NSMakeRange(start, nsString.length - start))
            if results.location == NSNotFound {
                result.append(nsString.substring(from: start))
                break
            }
            else {
                result.append(nsString.substring(with: NSMakeRange(start, results.location - start)))
                start = results.length + results.location
            }
        }
        return result
    }
    
    private static func reassembleURI(_ url: URL) -> String {
        var result = url.path
        if let query = url.query {
            result = result + "?" + query
        }
        return result
    }
}
