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
    public var accountCreationUser:AccountCreationUser?
    
    static let accessTokenKey = "accessToken"
    public var accessToken: String!
    
    static let accountIdKey = "accountId"
    var accountId: String!

    required public init?(configuration: Any? = nil, delegate: AccountDelegate?) {
        super.init()
        self.delegate = delegate
        baseURL = "api.dropboxapi.com"
    }
    
    public func toJSON() -> String? {
        var jsonDict = [String:String]()

        jsonDict[DropboxCreds.accessTokenKey] = self.accessToken
        // Don't need the accountId in the json because its saved as the credsId in the database.
        
        return JSONExtras.toJSONString(dict: jsonDict)
    }
    
    // Given existing Account info stored in the database, decide if we need to generate tokens. Token generation can be used for various purposes by the particular Account. E.g., For owning users to allow access to cloud storage data in offline manner. E.g., to allow access that data by sharing users.
    public func needToGenerateTokens(dbCreds:Account?) -> Bool {
        // 7/6/18; Previously, for Dropbox, I was returning false. But I want to deal with the case where a user a) deauthorizes the client app from using Dropbox, and then b) authorizes it again. This will make the access token we have in the database invalid. This will refresh it.
        // 8/25/20; While the above seems like a good idea, it is disconnected from `generateTokens` below, which is invoked when this returns true but below doesn't actually generate new tokens. So, changing this back to returning `false` for now.
        // Also see https://github.com/SyncServerII/ServerMain/issues/4 -- this was causing a crash when returning `true`.
        return false
    }
    
    private static let apiAccessTokenKey = "access_token"
    private static let apiTokenTypeKey = "token_type"
    
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
        
        // Both of these will be present-- both are necessary to authenticate with Dropbox.
        accountId = newerDropboxCreds.accountId
        accessToken = newerDropboxCreds.accessToken
    }
    
    public static func getProperties(fromHeaders headers:AccountHeaders) -> [String: Any] {
        var result = [String: Any]()
        
        if let accountId = headers[ServerConstants.HTTPAccountIdKey] {
            result[ServerConstants.HTTPAccountIdKey] = accountId
        }
        
        if let accessToken = headers[ServerConstants.HTTPOAuth2AccessTokenKey] {
            result[ServerConstants.HTTPOAuth2AccessTokenKey] = accessToken
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
            
        default:
            // Sharing users not allowed.
            assert(false)
        }
        
        return result
    }
}
