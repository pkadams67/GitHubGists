//
//  GitHubAPIManager.swift
//  GitHubGists
//
//  Created by Paul Kirk Adams on 7/21/16.
//  Copyright © 2016 Paul Kirk Adams. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON
import Locksmith

class GitHubAPIManager {
    
    static let sharedInstance = GitHubAPIManager()
    let clientID = "f7509cbf46f03af480c0"
    let clientSecret = "de78639088b59fc203a20c133c8ef126cb17bca0"
    var isLoadingOAuthToken = false
    static let ErrorDomain = "io.pkadams67.GitHubGists"
    var OAuthTokenCompletionHandler:(NSError? -> Void)?
    
    var OAuthToken: String? {
        set {
            guard let newValue = newValue else {
                let _ = try? Locksmith.deleteDataForUserAccount("github")
                return
            }
            guard let _ = try? Locksmith.updateData(["token": newValue], forUserAccount: "github") else {
                let _ = try? Locksmith.deleteDataForUserAccount("github")
                return
            }
        }
        get {
            Locksmith.loadDataForUserAccount("github")
            let dictionary = Locksmith.loadDataForUserAccount("github")
            return dictionary?["token"] as? String
        }
    }
    
    func clearCache() -> Void {
        let cache = NSURLCache.sharedURLCache()
        cache.removeAllCachedResponses()
    }
    
    func printPublicGists() -> Void {
        Alamofire.request(GistRouter.GetPublic())
            .responseString { response in
                if let receivedString = response.result.value {
                    print(receivedString)
                }
        }
    }
    
    func hasOAuthToken() -> Bool {
        if let token = self.OAuthToken {
            return !token.isEmpty
        }
        return false
    }
    
    func URLToStartOAuth2Login() -> NSURL? {
        let authPath:String = "https://github.com/login/oauth/authorize" +
            "?client_id=\(clientID)&scope=gist&state=TEST_STATE"
        guard let authURL:NSURL = NSURL(string: authPath) else {
            return nil
        }
        return authURL
    }
    
    func extractCodeFromOAuthStep1Response(url: NSURL) -> String? {
        let components = NSURLComponents(URL: url, resolvingAgainstBaseURL: false)
        var code:String?
        guard let queryItems = components?.queryItems else {
            return nil
        }
        for queryItem in queryItems {
            if (queryItem.name.lowercaseString == "code") {
                code = queryItem.value
                break
            }
        }
        return code
    }
    
    func parseOAuthTokenResponse(json: JSON) -> String? {
        var token: String?
        for (key, value) in json {
            switch key {
            case "access_token":
                token = value.string
            case "scope":
                print("SET SCOPE")
            case "token_type":
                print("CHECK IF BEARER")
            default:
                print("Got more than expected from OAuth token exchange")
                print(key)
            }
        }
        return token
    }
    
    func swapAuthCodeForToken(code: String) {
        let getTokenPath:String = "https://github.com/login/oauth/access_token"
        let tokenParams = ["client_id": clientID,
                           "client_secret": clientSecret,
                           "code": code]
        let jsonHeader = ["Accept": "application/json"]
        Alamofire.request(.POST, getTokenPath, parameters: tokenParams,
            headers: jsonHeader)
            .responseString { response in
                guard response.result.error == nil,
                    let receivedResults = response.result.value else {
                        print(response.result.error!)
                        self.OAuthTokenCompletionHandler?(NSError(domain: GitHubAPIManager.ErrorDomain,
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Couldn't obtain an OAuth token",
                                NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
                        self.isLoadingOAuthToken = false
                        return
                }
                guard let jsonData = receivedResults.dataUsingEncoding(NSUTF8StringEncoding,
                    allowLossyConversion: false) else {
                        print("no data received or data not JSON")
                        self.OAuthTokenCompletionHandler?(NSError(domain: GitHubAPIManager.ErrorDomain, code: -1,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Couldn't obtain an OAuth token",
                                NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
                        self.isLoadingOAuthToken = false
                        return
                }
                let jsonResults = JSON(data: jsonData)
                self.OAuthToken = self.parseOAuthTokenResponse(jsonResults)
                self.isLoadingOAuthToken = false
                if (self.hasOAuthToken()) {
                    self.OAuthTokenCompletionHandler?(nil)
                } else  {
                    self.OAuthTokenCompletionHandler?(NSError(domain: GitHubAPIManager.ErrorDomain,
                        code: -1, userInfo:
                        [NSLocalizedDescriptionKey: "Couldn't obtain an OAuth token",
                            NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
                }
        }
    }
    
    func processOAuthStep1Response(url: NSURL) {
        guard let code = extractCodeFromOAuthStep1Response(url) else {
            self.isLoadingOAuthToken = false
            self.OAuthTokenCompletionHandler?(NSError(domain: GitHubAPIManager.ErrorDomain, code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Couldn't obtain an OAuth code",
                    NSLocalizedRecoverySuggestionErrorKey: "Please retry your request"]))
            return
        }
        swapAuthCodeForToken(code)
    }
    
    func printMyStarredGistsWithOAuth2() -> Void {
        let alamofireRequest = Alamofire.request(GistRouter.GetMyStarred())
            .responseString { response in
                guard let receivedString = response.result.value else {
                    print(response.result.error!)
                    self.OAuthToken = nil
                    return
                }
                print(receivedString)
        }
        debugPrint(alamofireRequest)
    }
    
    func isAPIOnline(completionHandler: Bool -> Void) {
        Alamofire.request(.GET, GistRouter.baseURLString)
            .validate(statusCode: 200 ..< 300)
            .response { (request, response, data, error) in
                guard error == nil else {
                    completionHandler(false)
                    return
                }
                completionHandler(true)
        }
    }
    
    func fetchGists(urlRequest: URLRequestConvertible, completionHandler:
        (Result<[Gist], NSError>, String?) -> Void) {
        Alamofire.request(urlRequest)
            .responseArray { (response:Response<[Gist], NSError>) in
                if let urlResponse = response.response,
                    authError = self.checkUnauthorized(urlResponse) {
                    completionHandler(.Failure(authError), nil)
                    return
                }
                let next = self.parseNextPageFromHeaders(response.response)
                completionHandler(response.result, next)
        }
    }
    
    func fetchPublicGists(pageToLoad: String?, completionHandler:
        (Result<[Gist], NSError>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.GetAtPath(urlString), completionHandler: completionHandler)
        } else {
            fetchGists(GistRouter.GetPublic(), completionHandler: completionHandler)
        }
    }
    
    func fetchMyStarredGists(pageToLoad: String?, completionHandler:
        (Result<[Gist], NSError>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.GetAtPath(urlString), completionHandler: completionHandler)
        } else {
            fetchGists(GistRouter.GetMyStarred(), completionHandler: completionHandler)
        }
    }
    
    func fetchMyGists(pageToLoad: String?, completionHandler:
        (Result<[Gist], NSError>, String?) -> Void) {
        if let urlString = pageToLoad {
            fetchGists(GistRouter.GetAtPath(urlString), completionHandler: completionHandler)
        } else {
            fetchGists(GistRouter.GetMine(), completionHandler: completionHandler)
        }
    }
    
    func imageFromURLString(imageURLString: String, completionHandler:
        (UIImage?, NSError?) -> Void) {
        Alamofire.request(.GET, imageURLString)
            .response { (request, response, data, error) in
                guard let data = data else {
                    completionHandler(nil, nil)
                    return
                }
                let image = UIImage(data: data as NSData)
                completionHandler(image, nil)
        }
    }
    
    private func parseNextPageFromHeaders(response: NSHTTPURLResponse?) -> String? {
        guard let linkHeader = response?.allHeaderFields["Link"] as? String else {
            return nil
        }
        let components = linkHeader.characters.split {$0 == ","}.map { String($0) }
        for item in components {
            let rangeOfNext = item.rangeOfString("rel=\"next\"", options: [])
            guard rangeOfNext != nil else {
                continue
            }
            let rangeOfPaddedURL = item.rangeOfString("<(.*)>;", options: .RegularExpressionSearch)
            guard let range = rangeOfPaddedURL else {
                return nil
            }
            let nextURL = item.substringWithRange(range)
            let startIndex = nextURL.startIndex.advancedBy(1)
            let endIndex = nextURL.endIndex.advancedBy(-2)
            let urlRange = startIndex..<endIndex
            return nextURL.substringWithRange(urlRange)
        }
        return nil
    }
    
    func checkUnauthorized(urlResponse: NSHTTPURLResponse) -> (NSError?) {
        if (urlResponse.statusCode == 401) {
            self.OAuthToken = nil
            let lostOAuthError = NSError(domain: NSURLErrorDomain,
                                         code: NSURLErrorUserAuthenticationRequired,
                                         userInfo: [NSLocalizedDescriptionKey: "Not Logged In",
                                            NSLocalizedRecoverySuggestionErrorKey: "Please re-enter your GitHub credentials"])
            return lostOAuthError
        }
        return nil
    }
    
    func isGistStarred(gistId: String, completionHandler: Result<Bool, NSError> -> Void) {
        Alamofire.request(GistRouter.IsStarred(gistId))
            .validate(statusCode: [204])
            .response { (request, response, data, error) in
                if let error = error {
                    print(error)
                    if response?.statusCode == 404 {
                        completionHandler(.Success(false))
                        return
                    }
                    completionHandler(.Failure(error))
                    return
                }
                completionHandler(.Success(true))
        }
    }
    
    func starGist(gistId: String, completionHandler: (NSError?) -> Void) {
        Alamofire.request(GistRouter.Star(gistId))
            .validate(statusCode: [204])
            .response { (request, response, data, error) in
                guard error == nil else {
                    print(error)
                    return
                }
                completionHandler(error)
        }
    }
    
    func unstarGist(gistId: String, completionHandler: (NSError?) -> Void) {
        Alamofire.request(GistRouter.Unstar(gistId))
            .validate(statusCode: [204])
            .response { (request, response, data, error) in
                guard error == nil else {
                    print(error)
                    return
                }
                completionHandler(error)
        }
    }
    
    func deleteGist(gistId: String, completionHandler: (NSError?) -> Void) {
        Alamofire.request(GistRouter.Delete(gistId))
            .response { (request, response, data, error) in
                if let urlResponse = response, authError = self.checkUnauthorized(urlResponse) {
                    completionHandler(authError)
                    return
                }
                self.clearCache()
                completionHandler(error)
        }
    }
    
    func createNewGist(description: String, isPublic: Bool, files: [File],
                       completionHandler: (Result<Bool, NSError>) -> Void) {
        let publicString: String
        if isPublic {
            publicString = "true"
        } else {
            publicString = "false"
        }
        var filesDictionary = [String: AnyObject]()
        for file in files {
            if let name = file.filename, content = file.content {
                filesDictionary[name] = ["content": content]
            }
        }
        let parameters:[String: AnyObject] = [
            "description": description,
            "isPublic": publicString,
            "files": filesDictionary
        ]
        Alamofire.request(GistRouter.Create(parameters))
            .response { (request, response, data, error) in
                if let urlResponse = response, authError = self.checkUnauthorized(urlResponse) {
                    completionHandler(.Failure(authError))
                    return
                }
                guard error == nil else {
                    print(error)
                    completionHandler(.Failure(error!))
                    return
                }
                self.clearCache()
                completionHandler(.Success(true))
        }
    }
}