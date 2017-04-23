# Kitura-CredentialsHTTP
A plugin for the Kitura-Credentials framework that authenticates using HTTP Basic and Digest authentication.

[![Build Status - Master](https://travis-ci.org/IBM-Swift/Kitura.svg?branch=master)](https://travis-ci.org/IBM-Swift/Kitura-CredentialsHTTP)
![Mac OS X](https://img.shields.io/badge/os-Mac%20OS%20X-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)
![Apache 2](https://img.shields.io/badge/license-Apache2-blue.svg?style=flat)

## Summary
A plugin for [Kitura-Credentials](https://github.com/IBM-Swift/Kitura-Credentials) framework that authenticates using HTTP Basic and Digest authentication.

Our implementation of Digest authentication doesn't remember nonce values it generated, and doesn't check received request's nonce and nc. It uses MD5 algorithm, and the quality of protection (qop) is 'auth'.  


## Table of Contents
* [Swift version](#swift-version)
* [API](#api)
* [Example](#example)
* [License](#license)

## Swift version
The latest version of Kitura-CredentialsHTTP requires **Swift 3.0**. You can download this version of the Swift binaries by following this [link](https://swift.org/download/). Compatibility with other Swift versions is not guaranteed.

## API

### Basic authentication
To create an instance of `CredentialsHTTPBasic` plugin, a `VerifyPassword` function and an optional realm should be passed to the constructor:
```swift
public init (verifyPassword: @escaping VerifyPassword, realm: String?=nil)
```
`verifyPassword` is a function of type:
```swift
/// Type alias for the callback that verifies the userId and password.
/// If the authentication pair verifies, then a user profile is returned.
public typealias VerifyPassword = (userId: String, password: String, callback: @escaping (UserProfile?) -> Void) -> Void
```

### Digest authentication
CredentialsHTTPDigest initialization is similar to CredentialsHTTPBasic. In addition, an optional opaque value can be passed to the constructor.

## Example

This example shows how to use this plugin to authenticate requests with HTTP Basic authentication. HTTP Digest authentication is similar.
<br>

First create an instance of `Credentials` and an instance of `CredentialsHTTPBasic` plugin, supplying a `verifyPassword` function:

```swift
import Credentials
import CredentialsHTTP

let credentials = Credentials()
let users = ["John" : "12345", "Mary" : "qwerasdf"]
let basicCredentials = CredentialsHTTPBasic(verifyPassword: { userId, password, callback in
    if let storedPassword = users[userId], storedPassword == password {
        callback(UserProfile(id: userId, displayName: userId, provider: "HTTPBasic"))
    } else {
        callback(nil)
    }
})
```
Now register the plugin:
```swift
credentials.register(plugin: basicCredentials)
```
Connect `credentials` middleware to profile requests:
```swift
router.all("/profile", middleware: credentials)
```
If the authentication is successful, `request.userProfile` will contain user profile information:
```swift
router.get("/profile", handler:
    { request, response, next in
      ...
      let profile = request.userProfile
      let userId = profile.id
      let userName = profile.displayName
      ...
      next()
})
```

## Troubleshooting

Seeing error `ld: library not found for -lCHttpParser for architecture x86_64` on build?

To solve this, go to your Xcode build settings and add `$SRCROOT/.build/debug` to the Library Search Paths for the CredentialsHTTP targets.

## License
This library is licensed under Apache 2.0. Full license text is available in [LICENSE](LICENSE.txt).
