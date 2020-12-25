
import Foundation
import KituraNet
import LoggerAPI

extension DropboxCreds {
    enum CredentialsError : Swift.Error {
        case badStatusCode(HTTPStatusCode?)
        case couldNotObtainParameterFromJSON
        case nilAPIResult
        case badJSONResult
        case errorSavingCredsToDatabase
        case noRefreshToken
        case expiredOrRevokedAccessToken
        case noClientIdOrSecret
    }
    
    // Use the refresh token to generate a new access token.
    // If error is nil when the completion handler is called, then the accessToken of this object has been refreshed. It hasn't yet been persistently stored on this server. Uses delegate, if one is defined, to save refreshed creds to database.
    func refresh(completion:@escaping (Swift.Error?)->()) {
        /*
        Now, when you request a new token from the /oauth2/token endpoint, set the grant_type to refresh_token and provide your refresh_token as a parameter:

        curl https://api.dropbox.com/oauth2/token \
        -d grant_type=refresh_token \
        -d refresh_token=<YOUR_REFRESH_TOKEN> \
        -u <YOUR_APP_KEY>:<YOUR_APP_SECRET>
         */
        // From https://dropbox.tech/developers/migrating-app-permissions-and-access-tokens#implement-refresh-tokens
        // And see https://www.dropbox.com/developers/documentation/http/documentation#oauth2-token
        // POST method
        /*
        Calls to /oauth2/token need to be authenticated using the apps's key and secret. These can either be passed as application/x-www-form-urlencoded POST parameters (see parameters below) or via HTTP basic authentication. If basic authentication is used, the app key should be provided as the username, and the app secret should be provided as the password.
         */
        
        guard self.refreshToken != nil else {
            completion(CredentialsError.noRefreshToken)
            return
        }
        
        /*
        guard let clientId = configuration?.GoogleServerClientId,
            let clientSecret = configuration?.GoogleServerClientSecret else {
            Log.info("No client or secret from in configuration.")
            completion(CredentialsError.noClientIdOrSecret)
            return
        }

        let bodyParameters = "client_id=\(clientId)&client_secret=\(clientSecret)&refresh_token=\(self.refreshToken!)&grant_type=refresh_token"
        Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        
        self.apiCall(method: "POST", path: "/oauth2/v4/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedFailureBody: .json) { apiResult, statusCode, responseHeaders in

            // When the refresh token has been revoked
            // ["error": "invalid_grant", "error_description": "Token has been expired or revoked."]
            // See https://stackoverflow.com/questions/10576386
            
            // [1]
            if statusCode == HTTPStatusCode.badRequest,
                case .dictionary(let dict)? = apiResult,
                let error = dict["error"] as? String,
                error == "invalid_grant" {
                Log.error("Bad request: invalid_grant: \(dict)")
                completion(CredentialsError.expiredOrRevokedAccessToken)
                return
            }

            guard statusCode == HTTPStatusCode.OK else {
                Log.error("Bad status code: \(String(describing: statusCode))")
                completion(CredentialsError.badStatusCode(statusCode))
                return
            }
            
            guard apiResult != nil else {
                Log.error("API result was nil!")
                completion(CredentialsError.nilAPIResult)
                return
            }
            
            guard case .dictionary(let dictionary) = apiResult! else {
                Log.error("Bad JSON result: \(String(describing: apiResult))")
                completion(CredentialsError.badJSONResult)
                return
            }
            
            if let accessToken = dictionary[GoogleCreds.googleAPIAccessTokenKey] as? String {
                self.accessToken = accessToken
                Log.debug("Refreshed access token: \(accessToken)")
                
                if self.delegate == nil {
                    Log.warning("Delegate was nil-- could not save creds to database!")
                    completion(nil)
                    return
                }
                
                if self.delegate!.saveToDatabase(account: self) {
                    completion(nil)
                    return
                }
                
                completion(CredentialsError.errorSavingCredsToDatabase)
                return
            }
            
            Log.error("Could not obtain parameter from JSON!")
            completion(CredentialsError.couldNotObtainParameterFromJSON)
        }
        */
    }

#if false
    public override func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, additionalOptions: [ClientRequest.Options] = [], urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {
        
        var headers:[String:String] = additionalHeaders ?? [:]
        
        // We use this for some cases where we don't have an accessToken
        if let accessToken = self.accessToken {
            headers["Authorization"] = "Bearer \(accessToken)"
        }

        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, additionalOptions: additionalOptions, urlParameters: urlParameters, body: body,
            returnResultWhenNon200Code: returnResultWhenNon200Code,
            expectedSuccessBody: expectedSuccessBody,
            expectedFailureBody: expectedFailureBody) { (apiCallResult, statusCode, responseHeaders) in
        
            /* So far, I've seen two results from a Google expired or revoked refresh token:
                1) an unauthorized http status here followed by [1] in refresh.
                2) The following response here:
                    ["error":
                        ["code": 403,
                         "message": "Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.",
                         "errors":
                            [
                                ["message": "Daily Limit for Unauthenticated Use Exceeded. Continued use requires signup.",
                                "reason": "dailyLimitExceededUnreg",
                                "extendedHelp": "https://code.google.com/apis/console",
                                "domain": "usageLimits"]
                            ]
                        ]
                    ]
            */
            
            if statusCode == HTTPStatusCode.forbidden,
                case .dictionary(let dict)? = apiCallResult,
                let error = dict["error"] as? [String: Any],
                let errors = error["errors"] as? [[String: Any]],
                errors.count > 0,
                let reason = errors[0]["reason"] as? String,
                reason == "dailyLimitExceededUnreg" {
                
                Log.info("Google API Call: Daily limit exceeded.")
                
                completion(APICallResult.dictionary(
                    ["error":self.tokenRevokedOrExpired]),
                    .forbidden, nil)
                return
            }
            
            if statusCode == self.expiredAccessTokenHTTPCode && !self.alreadyRefreshed {
                self.alreadyRefreshed = true
                Log.info("Attempting to refresh Google access token...")
                
                self.refresh() { error in
                    if let error = error {
                        switch error {
                        case CredentialsError.expiredOrRevokedAccessToken:
                            Log.info("Refresh token expired or revoked")
                            completion(
                                APICallResult.dictionary(
                                    ["error":self.tokenRevokedOrExpired]),
                                .unauthorized, nil)
                        default:
                            Log.error("Failed to refresh access token: \(String(describing: error))")
                            completion(
                                APICallResult.dictionary(
                                    ["error":self.failedRefresh]), .unauthorized, nil)
                        }
                    }
                    else {
                        Log.info("Successfully refreshed access token!")

                        // Refresh was successful, update the authorization header and try the operation again.
                        if let accessToken = self.accessToken {
                            headers["Authorization"] = "Bearer \(accessToken)"
                        }
                        
                        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, additionalOptions: additionalOptions, urlParameters: urlParameters, body: body, returnResultWhenNon200Code: returnResultWhenNon200Code, expectedSuccessBody: expectedSuccessBody, expectedFailureBody: expectedFailureBody, completion: completion)
                    }
                }
            }
            else {
                completion(apiCallResult, statusCode, responseHeaders)
            }
        }
    }
#endif
}
