//
//  DropboxCreds.swift
//  Server
//
//  Created by Christopher G Prince on 12/3/17.
//

import Foundation
import ServerShared
import Kitura
import Credentials
import LoggerAPI
import KituraNet
import ServerAccount

public protocol DropboxCredsConfiguration {
    var DropboxAppKey:String? { get }
    var DropboxAppSecret:String? { get }
}

// For testing
protocol DropboxCredsDelegate: AnyObject {
    func attemptingAccessTokenRefresh(_ creds: DropboxCreds)
}

public class DropboxCreds : AccountAPICall, Account {
    public static var accountScheme:AccountScheme {
        return .dropbox
    }
    
    public var accountScheme:AccountScheme {
        return DropboxCreds.accountScheme
    }
    
    public var owningAccountsNeedCloudFolderName: Bool {
        return false
    }
    
    weak var delegate:AccountDelegate?
    weak var testingDelegate: DropboxCredsDelegate?
    
    public var accountCreationUser:AccountCreationUser?
    
    // This is to ensure that some error doesn't cause us to attempt to refresh the access token multiple times in a row. I'm assuming that for any one endpoint invocation, we'll at most need to refresh the access token a single time.
    // I never change this from true back to false because the DropboxCreds will only last, in real server operation, for the duration of an endpoint call (or similar operation). And since those are relatively short-lived an access token will never need refreshing more than once.
    var alreadyRefreshed = false
    
    static let accessTokenKey = "accessToken"
    public var accessToken: String!

    static let refreshTokenKey = "refreshToken"
    public var refreshToken: String!

    static let accountIdKey = "accountId"
    var accountId: String!

    var configuration: DropboxCredsConfiguration?

    required public init?(configuration: Any? = nil, delegate: AccountDelegate?) {
        super.init()
        self.delegate = delegate
        guard let configuration = configuration as? DropboxCredsConfiguration else {
            return nil
        }
        self.configuration = configuration
        baseURL = "api.dropboxapi.com"
    }
    
    public func toJSON() -> String? {
        var jsonDict = [String:String]()

        jsonDict[DropboxCreds.accessTokenKey] = self.accessToken
        jsonDict[DropboxCreds.refreshTokenKey] = self.refreshToken
        
        // Don't need the accountId in the json because its saved as the credsId in the database.
        
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    public func needToGenerateTokens(dbCreds:Account?) -> Bool {
        // 12/25/20; With the change by Dropbox to short-lived access tokens and refresh tokens, I have some new needs:
        // 1) When a refresh token arrives from the client, I need to save it to the database. (This may involve some checking to see if the refresh token has actually changed).
        // 2) When cloud storage access is taking place and the access token has expired, I need to be able to refresh the access token using the refresh token and save that new access token to the database.
        
        // Return true here to accomplish 1)-- to save new access token/refresh token arriving from the client.
        return true
    }
    
    public func generateTokens(completion:@escaping (Swift.Error?)->()) {
        // Not generating tokens, just saving.
        guard let delegate = delegate else {
            Log.warning("No Dropbox Creds delegate!")
            completion(nil)
            return
        }

        if delegate.saveToDatabase(account: self) {
            completion(nil)
            return
        }
        
        completion(GenerateTokensError.errorSavingCredsToDatabase)
    }
    
    public func merge(withNewer newerAccount:Account) {
        guard let newerDropboxCreds = newerAccount as? DropboxCreds else {
            Log.error("Wrong other type of creds!")
            assert(false)
            return
        }
        
        if let accountId = newerDropboxCreds.accountId {
            self.accountId = accountId
        }
        
        if let accessToken = newerDropboxCreds.accessToken {
            self.accessToken = accessToken
        }
        
        if let refreshToken = newerDropboxCreds.refreshToken {
            self.refreshToken = refreshToken
        }
    }
    
    public static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any] {
        var result = [String: Any]()
        
        if let accountId = headers[ServerConstants.HTTPAccountIdKey] {
            result[ServerConstants.HTTPAccountIdKey] = accountId
        }
        
        if let accessToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
        }
        
        if let refreshToken = headers[ServerConstants.httpRequestRefreshToken] {
            result[ServerConstants.httpRequestRefreshToken] = refreshToken
        }
        
        return result
    }
    
    public static func fromProperties(_ properties: AccountProperties, user:AccountCreationUser?, configuration: Any?, delegate:AccountDelegate?) -> Account? {
        guard let creds = DropboxCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        creds.accountCreationUser = user
        creds.accessToken =
            properties.properties[ServerConstants.HTTPOAuth2AccessTokenKey] as? String
        creds.refreshToken =             properties.properties[ServerConstants.httpRequestRefreshToken] as? String
            
        // Deal with deprecated ServerConstants.HTTPAccountIdKey
        if let accountId = properties.properties[ServerConstants.HTTPAccountIdKey] as? String {
            creds.accountId = accountId
        }
        else if let accountId = properties.properties[ServerConstants.HTTPAccountDetailsKey] as? String {
            creds.accountId = accountId
        }
        else {
            Log.error("Could not get accountId from properties.properties")
        }

        return creds
    }
    
    public static func fromJSON(_ json:String, user:AccountCreationUser, configuration: Any?, delegate:AccountDelegate?) throws -> Account? {
        guard let jsonDict = json.toJSONDictionary() as? [String:String] else {
            Log.error("Could not convert string to JSON [String:String]: \(json)")
            return nil
        }
        
        guard let result = DropboxCreds(configuration: configuration, delegate: delegate) else {
            return nil
        }
        
        result.accountCreationUser = user
        
        // Owning users have access token's in creds.
        switch user {
        case .user(let user) where AccountScheme(.accountName(user.accountType))?.userType == .owning:
            fallthrough
        case .userId(_):
            try setProperty(jsonDict:jsonDict, key: accessTokenKey) { value in
                result.accessToken = value
            }
            
            // 12/26/20; Not going to make it an error for refresh token not to be present-- in order to facilitate the Dropbox transition from short lived to long lived tokens. i.e., initially accounts will not have the refresh token in the database and don't want that to cause a failure.
            try setProperty(jsonDict:jsonDict, key: refreshTokenKey, required: false) { value in
                result.refreshToken = value
            }
            
        default:
            // Sharing users not allowed.
            assert(false)
        }
        
        return result
    }
    
    public override func apiCall(method:String, baseURL:String? = nil, path:String,
                 additionalHeaders: [String:String]? = nil, additionalOptions: [ClientRequest.Options] = [], urlParameters:String? = nil,
                 body:APICallBody? = nil,
                 returnResultWhenNon200Code:Bool = true,
                 expectedSuccessBody:ExpectedResponse? = nil,
                 expectedFailureBody:ExpectedResponse? = nil,
        completion:@escaping (_ result: APICallResult?, HTTPStatusCode?, _ responseHeaders: HeadersContainer?)->()) {
        
        apiCallAux(method:method, baseURL:baseURL, path:path,
                 additionalHeaders: additionalHeaders, additionalOptions: additionalOptions, urlParameters:urlParameters,
                 body:body,
                 returnResultWhenNon200Code:returnResultWhenNon200Code,
                 expectedSuccessBody:expectedSuccessBody,
                 expectedFailureBody:expectedFailureBody,
                completion:completion)
    }
}
