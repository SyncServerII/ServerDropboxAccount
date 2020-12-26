
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
    
    override func setUp() {
        super.setUp()
        HeliumLogger.use(.debug)
        
        // This should contain a valid refresh token
        // The accessToken in this is stale.
        plist = DropboxPlist.load(from: URL(fileURLWithPath: "../Private/ServerDropboxAccount/refreshToken.plist"))
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
        
        let exp2 = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure, .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // TEMPORARY
    func testExpiredAccessToken() {
        guard let creds = DropboxCreds(configuration: plist, delegate: nil) else {
            XCTFail()
            return
        }
        
        creds.accountId = plist.id
        creds.accessToken = plist.accessToken // expired access token

        let exp2 = expectation(description: "\(#function)\(#line)")
        
        creds.checkForFile(fileName: knownPresentFile) { result in
            switch result {
            case .success(let found):
                XCTAssert(found)
            case .failure, .accessTokenRevokedOrExpired:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testRefreshDueToCloudStorageCall() {
    }
}

