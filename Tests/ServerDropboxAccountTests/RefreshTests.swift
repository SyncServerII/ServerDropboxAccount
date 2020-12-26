
// Run on ubuntu with:
//  swift test --enable-test-discovery --filter ServerDropboxAccountTests.RefreshTests

import XCTest
import Foundation
import LoggerAPI
import HeliumLogger
import ServerShared
@testable import ServerDropboxAccount
import ServerAccount

class RefreshTests: XCTestCase {
    // In my Dropbox:
    let knownPresentFile = "IMPORTANT_README.txt"

    var plist:DropboxPlist!
    var accessTokenRefreshAttempts = 0
    
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
        
        // This should contain a valid refresh token
        // The accessToken in this is expired.
        guard let url = Bundle.module.url(forResource: "refreshToken", withExtension: "plist") else {
            XCTFail()
            return
        }
        
        plist = DropboxPlist.load(from: url)
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testRefreshAccessToken() {
        guard let creds = DropboxCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        guard let refreshToken = plist.refreshToken else {
            XCTFail()
            return
        }
        
        creds.refreshToken = refreshToken
        
        let exp = expectation(description: "exp")
        creds.refresh { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Need to have an access token; hadn't overtly set this-- must be set by refresh.
        guard let _ = creds.accessToken else {
            XCTFail()
            return
        }
        
        // Test the new access token.
        
        creds.accountId = plist.id
        
        creds.testingDelegate = self
        accessTokenRefreshAttempts = 0
        
        let exp2 = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        // Should not have refreshed in that API call.
        XCTAssert(accessTokenRefreshAttempts == 0)
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testExpiredAccessToken() {
        guard let creds = DropboxCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.testingDelegate = self
        accessTokenRefreshAttempts = 0
        
        creds.accountId = plist.id
        creds.accessToken = plist.token // expired access token
        creds.refreshToken = plist.refreshToken // valid refresh token
        
        let exp2 = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .failure(let fileCheckError):
                XCTFail("\(fileCheckError)")
            case .success:
                break
            }
            
            exp2.fulfill()
        }
        
        XCTAssert(accessTokenRefreshAttempts == 1)
        
        // creds should have the refreshed access token
        XCTAssert(creds.accessToken != plist.token)
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testTwoSuccessiveCloudStorageCallsWhenFirstRequiresAccessTokenRefresh() {
        guard let creds = DropboxCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.testingDelegate = self
        accessTokenRefreshAttempts = 0
        
        creds.accountId = plist.id
        creds.accessToken = plist.token // expired access token
        creds.refreshToken = plist.refreshToken // valid refresh token
        
        let exp2 = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .failure(let fileCheckError):
                XCTFail("\(fileCheckError)")
            case .success:
                break
            }
            
            exp2.fulfill()
        }
        
        XCTAssert(accessTokenRefreshAttempts == 1)
        
        // creds should have the refreshed access token
        XCTAssert(creds.accessToken != plist.token)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        // 2nd cloud storage call-- try to download the file. Expecting no access token refresh this time.
        accessTokenRefreshAttempts = 0
        
        let exp3 = expectation(description: "\(#function)\(#line)")
        
        creds.downloadFile(cloudFileName: knownPresentFile) { result in
            switch result {
            case .success:
                break
            case .accessTokenRevokedOrExpired, .failure, .fileNotFound:
                XCTFail()
            }
            
            exp3.fulfill()
        }
        
        XCTAssert(accessTokenRefreshAttempts == 0)
        
        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension RefreshTests: DropboxCredsDelegate {
    func attemptingAccessTokenRefresh(_ creds: DropboxCreds) {
        accessTokenRefreshAttempts += 1
    }
}
