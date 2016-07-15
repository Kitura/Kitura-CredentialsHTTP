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

import Foundation
import XCTest

import Kitura
import KituraNet
import KituraSys
import Credentials

@testable import CredentialsHTTP

class TestDigest : XCTestCase {
    
    static var allTests : [(String, (TestDigest) -> () throws -> Void)] {
        return [
                   ("testNoCredentials", testNoCredentials),
                   ("testBadCredentials", testBadCredentials),
                   ("testDigest", testDigest),
        ]
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    let host = "127.0.0.1"
    
    let router = TestDigest.setupRouter()
    
    func testNoCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", host: self.host, path: "/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response!.statusCode)")
                XCTAssertTrue(response!.headers["WWW-Authenticate"]!.first!.hasPrefix("Digest realm=\"test\", nonce="))
                XCTAssertTrue(response!.headers["WWW-Authenticate"]!.first!.hasSuffix("opaque=\"0a0b0c0d\", algorithm=\"MD5\", qop=\"auth\""))
                expectation.fulfill()
            })
        }
    }
    
    func testBadCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response!.statusCode)")
                XCTAssertTrue(response!.headers["WWW-Authenticate"]!.first!.hasPrefix("Digest realm=\"test\", nonce="))
                expectation.fulfill()
                }, headers: ["Authorization" : "Digest username=\"Mary\", realm=\"test\",nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\",    uri=\"/private/api/data\",  qop=auth,                       nc=00000001, cnonce=\"0a4f113b\", response=\"6629fae49393a05397450978507c4ef1\",opaque=\"0a0b0c0d\""])
        }
    }
    
    func testDigest() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(response!.statusCode)")
                do {
                    let body = try response!.readString()
                    XCTAssertEqual(body!,"<!DOCTYPE html><html><body><b>Mary is logged in with HTTPDigest</b></body></html>\n\n")
                }
                catch{
                    XCTFail("No response body")
                }

                expectation.fulfill()
                }, headers: ["Authorization" : "Digest username=\"Mary\", realm=\"test\",nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\",    uri=\"/private/api/data\",  qop=auth,                       nc=00000001, cnonce=\"0a4f113b\", response=\"59e3cce95566f4dd0262d812a12b9bb6\",  opaque=\"0a0b0c0d\""])
        }
    }
    
    static func setupRouter() -> Router {
        let router = Router()
        
        let apiCredentials = Credentials()
        let users = ["John" : "12345", "Mary" : "qwerasdf"]
        let digestCredentials = CredentialsHTTPDigest(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(userProfile: UserProfile(id: userId, displayName: userId, provider: "HTTPDigest"), password: storedPassword)
            }
            else {
                callback(userProfile: nil, password: nil)
            }
            }, realm: "test", opaque: "0a0b0c0d")
        
        apiCredentials.register(plugin: digestCredentials)
        
        let basicCredentials = CredentialsHTTPBasic(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(userProfile: UserProfile(id: userId, displayName: userId, provider: "HTTPBasic"), password: storedPassword)
            }
            else {
                callback(userProfile: nil, password: nil)
            }
            }, realm: "test")
        apiCredentials.register(plugin: basicCredentials)
        
        router.all("/private/*", middleware: BodyParser())
        router.all("/private/api", middleware: apiCredentials)
        router.get("/private/api/data", handler:
            { request, response, next in
                response.headers["Content-Type"] = "text/html; charset=utf-8"
                do {
                    if let profile = request.userProfile  {
                        try response.status(.OK).send("<!DOCTYPE html><html><body><b>\(profile.displayName) is logged in with \(profile.provider)</b></body></html>\n\n").end()
                        next()
                        return
                    }
                    else {
                        try response.status(.unauthorized).end()
                    }
                }
                catch {}
                next()
        })
        
        return router
    }
}
