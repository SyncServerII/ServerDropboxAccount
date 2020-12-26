
import Foundation
import KituraNet
import LoggerAPI
import ServerAccount

extension DropboxCreds {
    enum CredentialsError : Swift.Error {
        case badStatusCode(HTTPStatusCode?)
        case couldNotObtainParameterFromJSON
        case nilAPIResult
        case badJSONResult
        case errorSavingCredsToDatabase
        case noRefreshToken
        case expiredOrRevokedAccessToken
        case noKeyOrSecret
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
        // It looks like the base URL above is an error and it should be api.dropboxapi.com
        
        guard let refreshToken = refreshToken else {
            completion(CredentialsError.noRefreshToken)
            Log.info("No refresh token")
            return
        }
        
        guard let appKey = configuration?.DropboxAppKey,
            let appSecret = configuration?.DropboxAppSecret else {
            Log.info("No key or secret from in configuration.")
            completion(CredentialsError.noKeyOrSecret)
            return
        }

        let bodyParameters = "client_id=\(appKey)&client_secret=\(appSecret)&refresh_token=\(refreshToken)&grant_type=refresh_token"
        Log.debug("bodyParameters: \(bodyParameters)")
        
        let additionalHeaders = [
            "Content-Type": "application/x-www-form-urlencoded"
        ]
        
        self.apiCall(method: "POST", path: "/oauth2/token", additionalHeaders:additionalHeaders, body: .string(bodyParameters), expectedFailureBody: .json) { apiResult, statusCode, responseHeaders in

            // Don't yet know what response is expected with an expired access token.
            
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
            
            if let accessToken = dictionary["access_token"] as? String {
                self.accessToken = accessToken
                Log.debug("Refreshed access token: \(accessToken)")
                
                guard let delegate = self.delegate else {
                    Log.warning("Delegate was nil-- could not save creds to database!")
                    completion(nil)
                    return
                }
                
                if delegate.saveToDatabase(account: self) {
                    completion(nil)
                    return
                }
                
                completion(CredentialsError.errorSavingCredsToDatabase)
                return
            }
            
            Log.error("Could not obtain parameter from JSON!")
            completion(CredentialsError.couldNotObtainParameterFromJSON)
        }
    }
    
    /*
    https://www.dropbox.com/developers/documentation/http/documentation
    
    401	Bad or expired token. This can happen if the access token is expired or if the access token has been revoked by Dropbox or the user. To fix this, you should re-authenticate the user.
        The Content-Type of the response is JSON of typeAuthError
        
            {
                "error_summary": "expired_access_token/...",
                "error": {
                    ".tag": "expired_access_token"
                }
            }
     */

    func apiCallAux(method:String, baseURL:String? = nil, path:String,
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
        
        let expiredAccessTokenHTTPCode:HTTPStatusCode = .badRequest
        let tokenRevokedOrExpired = "Token revoked or expired"
        let failedRefresh = "Failed refresh"
        
        super.apiCall(method: method, baseURL: baseURL, path: path, additionalHeaders: headers, additionalOptions: additionalOptions, urlParameters: urlParameters, body: body,
            returnResultWhenNon200Code: returnResultWhenNon200Code,
            expectedSuccessBody: expectedSuccessBody,
            expectedFailureBody: expectedFailureBody) { (apiCallResult, statusCode, responseHeaders) in
            
            if statusCode == expiredAccessTokenHTTPCode && !self.alreadyRefreshed {
                self.alreadyRefreshed = true
                Log.info("Attempting to refresh Dropbox access token...")
                
                self.refresh() { error in
                    if let error = error {
                        switch error {
                        case CredentialsError.expiredOrRevokedAccessToken:
                            Log.info("Refresh token expired or revoked")
                            completion(
                                APICallResult.dictionary(
                                    ["error":tokenRevokedOrExpired]),
                                .unauthorized, nil)
                        default:
                            Log.error("Failed to refresh access token: \(String(describing: error))")
                            completion(
                                APICallResult.dictionary(
                                    ["error":failedRefresh]), .unauthorized, nil)
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
}
