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
import Credentials

@testable import CredentialsHTTP

class TestBasic : XCTestCase {
    
    static var allTests : [(String, (TestBasic) -> () throws -> Void)] {
        return [
                   ("testNoCredentials", testNoCredentials),
                   ("testBadCredentials", testBadCredentials),
                   ("testBasic", testBasic),
        ]
    }
    
    override func setUp() {
        doSetUp()
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    let host = "127.0.0.1"
    
    let router = TestBasic.setupRouter()
    
    func testNoCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", host: self.host, path: "/private/apiv1/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response?.statusCode)")
                XCTAssertEqual(response?.headers["WWW-Authenticate"]?.first, "Basic realm=\"test\"")
                expectation.fulfill()
            })
        }

        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", host: self.host, path: "/private/apiv2/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response?.statusCode)")
                XCTAssertEqual(response?.headers["WWW-Authenticate"]?.first, "Basic realm=\"test\"")
                expectation.fulfill()
            })
        }
    }
    
    func testBadCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/apiv1/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response?.statusCode)")
                XCTAssertEqual(response?.headers["WWW-Authenticate"]?.first, "Basic realm=\"test\"")
                expectation.fulfill()
                }, headers: ["Authorization" : "Basic QWxhZGRpbjpPcGVuU2VzYW1l"])
        }
        
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/apiv2/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response?.statusCode)")
                XCTAssertEqual(response?.headers["WWW-Authenticate"]?.first, "Basic realm=\"test\"")
                expectation.fulfill()
                }, headers: ["Authorization" : "Basic QWxhZGRpbjpPcGVuU2VzYW1l"])
        }
        
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/apiv2/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response?.statusCode)")
                XCTAssertEqual(response?.headers["WWW-Authenticate"]?.first, "Basic realm=\"test\"")
                expectation.fulfill()
            }, headers: ["Authorization" : "Basic"])
        }
    }
    
    func testBasic() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/apiv1/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(response?.statusCode)")
                do {
                    let body = try response?.readString()
                    XCTAssertEqual(body,"<!DOCTYPE html><html><body><b>Mary is logged in with HTTPBasic</b></body></html>\n\n")
                }
                catch{
                    XCTFail("No response body")
                }
                expectation.fulfill()
                }, headers: ["Authorization" : "Basic TWFyeTpxd2VyYXNkZg=="])
        }
        
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/apiv2/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response?.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(response?.statusCode)")
                do {
                    let body = try response?.readString()
                    XCTAssertEqual(body,"<!DOCTYPE html><html><body><b>Mary is logged in with HTTPBasic</b></body></html>\n\n")
                }
                catch{
                    XCTFail("No response body")
                }
                expectation.fulfill()
                }, headers: ["Authorization" : "Basic TWFyeTpxd2VyYXNkZg=="])
        }
    }
    
    static func setupRouter() -> Router {
        let router = Router()
        
        // v1 api uses basic authentication with userProfileLoader callback which is deprecated for v2
        let apiCredentials_v1 = Credentials()
        let users = ["John" : "12345", "Mary" : "qwerasdf"]
        let basicCredentials_v1 = CredentialsHTTPBasic(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(UserProfile(id: userId, displayName: userId, provider: "HTTPBasic"), storedPassword)
            }
            else {
                callback(nil, nil)
            }
            }, realm: "test")
        apiCredentials_v1.register(plugin: basicCredentials_v1)
        
        let digestCredentials = CredentialsHTTPDigest(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(UserProfile(id: userId, displayName: userId, provider: "HTTPDigest"), storedPassword)
            }
            else {
                callback(nil, nil)
            }
            }, opaque: "0a0b0c0d", realm: "Kitura-users")
        
        apiCredentials_v1.register(plugin: digestCredentials)
        
        router.all("/private/*", middleware: BodyParser())
        router.all("/private/apiv1", middleware: apiCredentials_v1)
        router.get("/private/apiv1/data", handler:
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

        // v2 api uses basic authentication with verifyPassword callback which replaces the userProfileLoader
        let apiCredentials_v2 = Credentials()
        let basicCredentials_v2 = CredentialsHTTPBasic(verifyPassword: { userId, password, callback in
            if let storedPassword = users[userId] {
                if (storedPassword == password) {
                    callback(UserProfile(id: userId, displayName: userId, provider: "HTTPBasic"))
                }
            }
            // else if userId or password doesnt match
            callback(nil)
            }, realm: "test")
        apiCredentials_v2.register(plugin: basicCredentials_v2)
        
        router.all("/private/apiv2", middleware: apiCredentials_v2)
        router.get("/private/apiv2/data", handler:
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
