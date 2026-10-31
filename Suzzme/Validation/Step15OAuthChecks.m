#import <Foundation/Foundation.h>
#import "OIDAuthorizationRequest.h"
#import "OIDAuthorizationResponse.h"
#import "OIDAuthorizationService.h"
#import "OIDExternalUserAgent.h"
#import "OIDExternalUserAgentSession.h"
#import "OIDServiceConfiguration.h"
#import "OIDTokenRequest.h"
#import "OIDTokenResponse.h"

// The installed AppAuth implementation runs; this agent opens no browser,
// requests no token, sends no traffic and never represents a Google account.
@interface Step15Agent : NSObject <OIDExternalUserAgent>
@end
@implementation Step15Agent
- (BOOL)presentExternalUserAgentRequest:(id<OIDExternalUserAgentRequest>)request session:(id<OIDExternalUserAgentSession>)session { return YES; }
- (void)dismissExternalUserAgentAnimated:(BOOL)animated completion:(void (^)(void))completion { completion(); }
@end
static int passed = 0, failed = 0;
static void check(BOOL value, const char *label) { if (value) { passed++; printf("PASS %s\n",label); } else { failed++; printf("FAIL %s\n",label); } }
static OIDAuthorizationRequest *request(void) {
    OIDServiceConfiguration *configuration = [[OIDServiceConfiguration alloc] initWithAuthorizationEndpoint:[NSURL URLWithString:@"https://example.test/authorize"] tokenEndpoint:[NSURL URLWithString:@"https://example.test/token"]];
    return [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration clientId:@"synthetic-public-client" scopes:@[@"openid"] redirectURL:[NSURL URLWithString:@"suzzme-fixture:/oauthredirect"] responseType:@"code" additionalParameters:nil];
}
int main(void) { @autoreleasepool {
    OIDAuthorizationRequest *first = request(), *second = request();
    check(first.state.length >= 32 && ![first.state isEqual:second.state], "per-request unpredictable OAuth state");
    check(first.codeVerifier.length >= 43 && first.codeVerifier.length <= 128, "PKCE verifier meets RFC length");
    check(![first.codeVerifier isEqual:second.codeVerifier], "distinct per-request PKCE verifier");
    check([first.codeChallengeMethod isEqual:@"S256"], "PKCE uses S256");
    check([first.codeChallenge isEqual:[OIDAuthorizationRequest codeChallengeS256ForVerifier:first.codeVerifier]], "challenge derives from actual verifier");
    check([[OIDAuthorizationRequest codeChallengeS256ForVerifier:@"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"] isEqual:@"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"], "RFC7636 S256 vector");
    NSString *url = first.externalUserAgentRequestURL.absoluteString;
    check([url containsString:@"code_challenge_method=S256"] && [url containsString:@"state="], "authorization URL carries state and challenge");
    check(![url containsString:first.codeVerifier], "authorization URL excludes secret verifier");
    OIDTokenRequest *refresh = [[OIDTokenRequest alloc] initWithConfiguration:first.configuration
        grantType:@"refresh_token" authorizationCode:nil redirectURL:nil clientID:first.clientID
        clientSecret:nil scope:nil refreshToken:@"synthetic-refresh-credential" codeVerifier:nil additionalParameters:nil];
    NSURLRequest *refreshRequest = refresh.URLRequest;
    NSString *refreshBody = [[NSString alloc] initWithData:refreshRequest.HTTPBody encoding:NSUTF8StringEncoding];
    check([refreshRequest.HTTPMethod isEqual:@"POST"] && [refreshRequest.URL isEqual:first.configuration.tokenEndpoint], "SDK refresh targets configured token endpoint by POST");
    check([refreshBody containsString:@"grant_type=refresh_token"] && [refreshBody containsString:@"refresh_token=synthetic-refresh-credential"], "SDK constructs actual refresh grant body");
    check(![refreshRequest.URL.absoluteString containsString:@"synthetic-refresh-credential"] && ![refreshBody containsString:@"client_secret="], "public-client refresh excludes URL credentials and client secret");
    OIDTokenResponse *expired = [[OIDTokenResponse alloc] initWithRequest:refresh parameters:@{@"access_token":@"synthetic-access", @"token_type":@"Bearer", @"expires_in":@(-10)}];
    check(expired.accessTokenExpirationDate.timeIntervalSinceNow < 0, "SDK response expiry is observable before token use");
    Step15Agent *agent = [Step15Agent new];
    __block int callbacks = 0; __block OIDAuthorizationResponse *response; __block NSError *error;
    id<OIDExternalUserAgentSession> session = [OIDAuthorizationService presentAuthorizationRequest:first externalUserAgent:agent callback:^(OIDAuthorizationResponse *r,NSError *e) { callbacks++; response = r; error = e; }];
    check(![session resumeExternalUserAgentFlowWithURL:[NSURL URLWithString:@"other:/oauthredirect?state=x&code=x"]] && callbacks == 0, "wrong callback scheme cannot resume flow");
    check([session resumeExternalUserAgentFlowWithURL:[NSURL URLWithString:@"suzzme-fixture:/oauthredirect?state=wrong&code=synthetic"]], "matching redirect receives state validation");
    check(callbacks == 1 && response == nil && error != nil, "mismatched state rejects authorization");
    check(![session resumeExternalUserAgentFlowWithURL:[NSURL URLWithString:@"suzzme-fixture:/oauthredirect?state=wrong&code=synthetic"]] && callbacks == 1, "duplicate callback cannot authorize twice");
    callbacks = 0; response = nil; error = nil;
    session = [OIDAuthorizationService presentAuthorizationRequest:second externalUserAgent:agent callback:^(OIDAuthorizationResponse *r,NSError *e) { callbacks++; response = r; error = e; }];
    NSURL *correct = [NSURL URLWithString:[NSString stringWithFormat:@"suzzme-fixture:/oauthredirect?state=%@&code=synthetic",second.state]];
    check([session resumeExternalUserAgentFlowWithURL:correct] && callbacks == 1 && response != nil && error == nil, "correct owned state returns authorization code without exchange");
    check(![session resumeExternalUserAgentFlowWithURL:correct] && callbacks == 1, "completed authorization callback cannot replay");
    callbacks = 0; response = nil; error = nil;
    session = [OIDAuthorizationService presentAuthorizationRequest:request() externalUserAgent:agent callback:^(OIDAuthorizationResponse *r,NSError *e) { callbacks++; response = r; error = e; }];
    [session cancel];
    check(callbacks == 1 && response == nil && error != nil, "cancellation terminates authorization without token");
    printf("Step 15 OAuth SDK: %d passed / %d failed. No Google sign-in, token exchange or live account acceptance.\n",passed,failed);
    return failed ? 1 : 0;
} }
