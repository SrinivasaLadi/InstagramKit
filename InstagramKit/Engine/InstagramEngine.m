//
//    Copyright (c) 2013 Shyam Bhat
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy of
//    this software and associated documentation files (the "Software"), to deal in
//    the Software without restriction, including without limitation the rights to
//    use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
//    the Software, and to permit persons to whom the Software is furnished to do so,
//    subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
//    FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
//    COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
//    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
//    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "InstagramEngine.h"
#import "AFNetworking.h"
#import "InstagramUser.h"
#import "InstagramMedia.h"
#import "InstagramComment.h"
#import "InstagramTag.h"
#import "InstagramPaginationInfo.h"

#define kKeyClientID @"client_id"
#define kKeyAccessToken @"access_token"

NSString *const kInstagramKitAppClientIdConfigurationKey = @"InstagramKitAppClientId";
NSString *const kInstagramKitAppRedirectUrlConfigurationKey = @"InstagramKitAppRedirectURL";

NSString *const kInstagramKitBaseUrlConfigurationKey = @"InstagramKitBaseUrl";
NSString *const kInstagramKitAuthorizationUrlConfigurationKey = @"InstagramKitAuthorizationUrl";

NSString *const kInstagramKitBaseUrlDefault = @"https://api.instagram.com/v1/";
NSString *const kInstagramKitBaseUrl __deprecated = @"https://api.instagram.com/v1/";

NSString *const kInstagramKitAuthorizationUrlDefault = @"https://api.instagram.com/oauth/authorize/";
NSString *const kInstagramKitAuthorizationUrl __deprecated = @"https://api.instagram.com/oauth/authorize/";
NSString *const kInstagramKitErrorDomain = @"InstagramKitErrorDomain";


/* From the Documentation :
 
 Relationships are expressed using the following terms:
 outgoing_status: Your relationship to the user. Can be "follows", "requested", "none".
 incoming_status: A user's relationship to you. Can be "followed_by", "requested_by", "blocked_by_you", "none".
 
 */

NSString *const kRelationshipOutgoingStatusKey = @"outgoing_status";
NSString *const kRelationshipOutStatusFollows = @"follows";
NSString *const kRelationshipOutStatusRequested = @"requested";
NSString *const kRelationshipOutStatusNone = @"none";

NSString *const kRelationshipIncomingStatusKey = @"incoming_status";
NSString *const kRelationshipInStatusFollowedBy = @"followed_by";
NSString *const kRelationshipInStatusRequestedBy = @"requested_by";
NSString *const kRelationshipInStatusBlockedByYou = @"blocked_by_you";
NSString *const kRelationshipInStatusNone = @"none";

NSString *const kRelationshipUserIsPrivateKey = @"target_user_is_private";

NSString *const kRelationshipActionKey = @"action";
NSString *const kRelationshipActionFollow = @"follow";
NSString *const kRelationshipActionUnfollow = @"unfollow";
NSString *const kRelationshipActionBlock = @"block";
NSString *const kRelationshipActionUnblock = @"unblock";
NSString *const kRelationshipActionApprove = @"approve";
NSString *const kRelationshipActionDeny = @"deny";


#define kData @"data"
#define kPagination @"pagination"


typedef enum
{
    kPaginationMaxId,
    kPaginationMaxLikeId,
    kPaginationMaxTagId,
} MaxIdKeyType;

@interface InstagramEngine()
{
    dispatch_queue_t mBackgroundQueue;
}

+ (NSDictionary*) sharedEngineConfiguration;

@property (nonatomic, copy) InstagramLoginBlock instagramLoginBlock;
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
@property (nonatomic, strong) AFHTTPRequestOperationManager *httpManager;
#else
@property (nonatomic, strong) AFHTTPSessionManager *httpManager;
#endif

@end

@implementation InstagramEngine

#pragma mark - Initializers -

+ (InstagramEngine *)sharedEngine {
    static InstagramEngine *_sharedEngine = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _sharedEngine = [[InstagramEngine alloc] init];
    });
    return _sharedEngine;
}

+ (NSDictionary*) sharedEngineConfiguration {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"InstagramKit" withExtension:@"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfURL:url];
    dict = dict ? dict : [[NSBundle mainBundle] infoDictionary];
    return dict;
}

- (id)init {
    if (self = [super init])
    {
        NSDictionary *sharedEngineConfiguration = [InstagramEngine sharedEngineConfiguration];
        id url = nil;
        url = sharedEngineConfiguration[kInstagramKitBaseUrlConfigurationKey];
        
        if (url) {
            url = [NSURL URLWithString:url];
        } else {
            url = [NSURL URLWithString:kInstagramKitBaseUrlDefault];
        }
        
        NSAssert(url, @"Base URL not valid: %@", sharedEngineConfiguration[kInstagramKitBaseUrlConfigurationKey]);
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
        self.httpManager = [[AFHTTPRequestOperationManager alloc] initWithBaseURL:url];
#else
        self.httpManager = [[AFHTTPSessionManager alloc] initWithBaseURL:url];
#endif

        self.appClientID =  sharedEngineConfiguration[kInstagramKitAppClientIdConfigurationKey];
        self.appRedirectURL = sharedEngineConfiguration[kInstagramKitAppRedirectUrlConfigurationKey];

        url = sharedEngineConfiguration[kInstagramKitAuthorizationUrlConfigurationKey];
        self.authorizationURL = url ? url : kInstagramKitAuthorizationUrlDefault;

        mBackgroundQueue = dispatch_queue_create("background", NULL);

        self.httpManager.responseSerializer = [[AFJSONResponseSerializer alloc] init];

        BOOL validClientId = IKNotNull(self.appClientID) && ![self.appClientID isEqualToString:@""] && ![self.appClientID isEqualToString:@"<Client Id here>"];
        NSAssert(validClientId, @"Invalid Instagram Client ID.");
        NSAssert([NSURL URLWithString:self.appRedirectURL], @"App Redirect URL invalid: %@", self.appRedirectURL);
        NSAssert([NSURL URLWithString:self.authorizationURL], @"Authorization URL invalid: %@", self.authorizationURL);
    }
    return self;
}

#pragma mark - Login -


- (void)loginWithBlock:(InstagramLoginBlock)block
{
    [self loginWithScope:IKLoginScopeBasic completionBlock:block];
}

- (void)loginWithScope:(IKLoginScope)scope completionBlock:(InstagramLoginBlock)block
{
    NSMutableDictionary *params = [@{kKeyClientID: self.appClientID,
                                     @"redirect_uri": self.appRedirectURL,
                                     @"response_type": @"token"} mutableCopy];
    
    if(scope)
    {
        params[@"scope"] = [InstagramEngine stringForScope:scope];
    }
    
    NSMutableArray *queryElements = [NSMutableArray arrayWithCapacity:params.count];
    [params enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [queryElements addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }];
    
    NSString *queryString = [queryElements componentsJoinedByString:@"&"];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?%@",
        self.authorizationURL, queryString]];
    
    self.instagramLoginBlock = block;

    [[UIApplication sharedApplication] openURL:url];
}

+ (NSString *)stringForScope:(IKLoginScope)scope
{
    
    NSArray *typeStrings = @[@"basic",@"comments",@"relationships",@"likes"];
    NSMutableArray *strings = [NSMutableArray arrayWithCapacity:4];
    
#define kBitsUsedByIKLoginScope 4
    
    for (NSUInteger i=0; i < kBitsUsedByIKLoginScope; i++)
    {
        NSUInteger enumBitValueToCheck = 1 << i;
        if (scope & enumBitValueToCheck)
            [strings addObject:[typeStrings objectAtIndex:i]];
    }
    if (!strings.count) {
        return @"basic";
    }
    
    return [strings componentsJoinedByString:@"+"];
    
}

- (void)cancelLogin
{
    if (self.instagramLoginBlock)
    {
        NSString *localizedDescription = NSLocalizedString(@"User canceled Instagram Login.", @"Error notification for Instagram Login cancelation.");
        NSError *error = [NSError errorWithDomain:kInstagramKitErrorDomain code:kInstagramKitErrorCodeUserCancelled userInfo:@{
                                                                                                                               NSLocalizedDescriptionKey: localizedDescription
                                                                                                                               }];
        self.instagramLoginBlock(error);
    }
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{

    NSURL *appRedirectURL = [NSURL URLWithString:self.appRedirectURL];

    if (![appRedirectURL.scheme isEqual:url.scheme] || ![appRedirectURL.host isEqual:url.host])
    {
        return NO;
    }
    
    NSString* accessToken = [self queryStringParametersFromString:url.fragment][@"access_token"];
    if (accessToken)
    {
        self.accessToken = accessToken;
        if (self.instagramLoginBlock) self.instagramLoginBlock(nil);
    }
    else if (self.instagramLoginBlock)
    {
        NSString *localizedDescription = NSLocalizedString(@"Authorization not granted.", @"Error notification to indicate Instagram OAuth token was not provided.");
        NSError *error = [NSError errorWithDomain:kInstagramKitErrorDomain code:kInstagramKitErrorCodeAccessNotGranted userInfo:@{
            NSLocalizedDescriptionKey: localizedDescription
        }];
        self.instagramLoginBlock(error);
    }
    self.instagramLoginBlock = nil;
    return YES;
}

- (void)logout
{
//    Clear all cookies so the next time the user wishes to switch accounts,
//    they can do so
    
    NSHTTPCookie *cookie;
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (cookie in [storage cookies]) {
        [storage deleteCookie:cookie];
    }
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    self.accessToken = nil;
    
    NSLog(@"User is now logged out");
    
#ifdef DEBUG
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Logged out" message:@"The user is now logged out. Proceed with dismissing the view. This message only appears in the debug environment." delegate:nil cancelButtonTitle:@"Okay" otherButtonTitles:nil, nil];
    
    [alert show];
    
#endif
    
}

-(NSDictionary*)queryStringParametersFromString:(NSString*)string {

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for (NSString * param in [string componentsSeparatedByString:@"&"])
    {
        NSArray *pairs = [param componentsSeparatedByString:@"="];
        if ([pairs count] != 2) continue;
        NSString *key = [pairs[0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *value = [pairs[1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        [dict setObject:value forKey:key];
    }
    return dict;
}


#pragma mark - Base Calls -


- (void)getPath:(NSString *)path
     parameters:(NSDictionary *)parameters
  responseModel:(Class)modelClass
        success:(void (^)(id response, InstagramPaginationInfo *paginationInfo))success
        failure:(void (^)(NSError* error, NSInteger statusCode))failure
{

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:parameters];

    if (self.accessToken) {
        [params setObject:self.accessToken forKey:kKeyAccessToken];
    }
    else
    {
        [params setObject:self.appClientID forKey:kKeyClientID];
    }
    
    NSString *percentageEscapedPath = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    [self.httpManager GET:percentageEscapedPath
        parameters:params
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
           success:^(AFHTTPRequestOperation *operation, id responseObject) {
#else
           success:^(NSURLSessionDataTask *task, id responseObject) {
#endif
               NSDictionary *responseDictionary = (NSDictionary *)responseObject;
               NSDictionary *pInfo = responseDictionary[kPagination];
               InstagramPaginationInfo *paginationInfo = (pInfo)?[[InstagramPaginationInfo alloc] initWithInfo:pInfo andObjectType:modelClass]: nil;
               BOOL multiple = ([responseDictionary[kData] isKindOfClass:[NSArray class]]);
               if (multiple) {
                   NSArray *responseObjects = responseDictionary[kData];
                   NSMutableArray*objects = [NSMutableArray arrayWithCapacity:responseObjects.count];
                   dispatch_async(mBackgroundQueue, ^{
                       if (modelClass) {
                           for (NSDictionary *info in responseObjects) {
                               id model = [[modelClass alloc] initWithInfo:info];
                               [objects addObject:model];
                           }
                       }
                       dispatch_async(dispatch_get_main_queue(), ^{
                           success(objects, paginationInfo);
                       });
                   });
               }
               else {
                   id model = nil;
                   if (modelClass && IKNotNull(responseDictionary[kData]))
                   {
                       if (modelClass == [NSDictionary class]) {
                           model = [[NSDictionary alloc] initWithDictionary:responseDictionary[kData]];
                       }
                       else
                       {
                           model = [[modelClass alloc] initWithInfo:responseDictionary[kData]];
                       }
                   }
                   success(model, paginationInfo);
               }
           }
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
           failure:^(AFHTTPRequestOperation *operation, NSError *error) {
               failure(error,[[operation response] statusCode]);
#else
           failure:^(NSURLSessionDataTask *task, NSError *error) {
               failure(error,((NSHTTPURLResponse *)[task response]).statusCode);
#endif
           }];
}

- (void)postPath:(NSString *)path
     parameters:(NSDictionary *)parameters
   responseModel:(Class)modelClass
        success:(void (^)(NSDictionary *responseObject))success
        failure:(void (^)(NSError* error, NSInteger statusCode))failure
{
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:parameters];
    if (self.accessToken) {
        [params setObject:self.accessToken forKey:kKeyAccessToken];
    }
    else
        [params setObject:self.appClientID forKey:kKeyClientID];
    
    [self.httpManager POST:path
                    parameters:params
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
                       success:^(AFHTTPRequestOperation *operation, id responseObject) {
#else
                       success:^(NSURLSessionDataTask *task, id responseObject) {
#endif
                           NSDictionary *responseDictionary = (NSDictionary *)responseObject;
                           success(responseDictionary);
                       }
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
                       failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                           failure(error,[[operation response] statusCode]);
#else
                       failure:^(NSURLSessionDataTask *task, NSError *error) {
                           failure(error,((NSHTTPURLResponse*)[task response]).statusCode);
#endif
                       }];
}


- (void)deletePath:(NSString *)path
      parameters:(NSDictionary *)parameters
   responseModel:(Class)modelClass
         success:(void (^)(void))success
         failure:(void (^)(NSError* error, NSInteger statusCode))failure
{
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:parameters];
    if (self.accessToken) {
        [params setObject:self.accessToken forKey:kKeyAccessToken];
    }
    else
        [params setObject:self.appClientID forKey:kKeyClientID];
    [self.httpManager DELETE:path
                  parameters:params
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
                     success:^(AFHTTPRequestOperation *operation, id responseObject) {
#else
                     success:^(NSURLSessionDataTask *task, id responseObject) {
#endif
                         if (success) {
                             success();
                         }
                     }
#if (__IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_7_0)
                     failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                         if (failure) {
                             failure(error,[[operation response] statusCode]);
#else
                     failure:^(NSURLSessionDataTask *task, NSError *error) {
                         if (failure) {
                             failure(error,((NSHTTPURLResponse*)[task response]).statusCode);
#endif
                         }
                     }];
}

- (NSDictionary *)parametersFromCount:(NSInteger)count maxId:(NSString *)maxId andMaxIdType:(MaxIdKeyType)keyType
{
    NSMutableDictionary *params = [[NSMutableDictionary alloc] initWithObjectsAndKeys:[NSString stringWithFormat:@"%ld",(long)count], kCount, nil];
    if (maxId) {
        NSString *key = nil;
        switch (keyType) {
            case kPaginationMaxId:
                key = kMaxId;
                break;
            case kPaginationMaxLikeId:
                key = kMaxLikeId;
                break;
            case kPaginationMaxTagId:
                key = kMaxTagId;
                break;
        }
        [params setObject:maxId forKey:key];
    }
    return [NSDictionary dictionaryWithDictionary:params];
}


#pragma mark - Media -


- (void)getMedia:(NSString *)mediaId
     withSuccess:(void (^)(InstagramMedia *media))success
         failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"media/%@",mediaId] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			InstagramMedia *media = response;
			success(media);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getPopularMediaWithSuccess:(InstagramMediaBlock)success
                           failure:(InstagramFailureBlock)failure
{
    [self getPath:@"media/popular" parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        NSArray *objects = response;
        if(success)
		{
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaAtLocation:(CLLocationCoordinate2D)location
               withSuccess:(InstagramMediaBlock)success
                   failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"media/search?lat=%f&lng=%f",location.latitude,location.longitude] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaAtLocation:(CLLocationCoordinate2D)location count:(NSInteger)count maxId:(NSString *)maxId
               withSuccess:(InstagramMediaBlock)success
                   failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxId];
    [self getPath:[NSString stringWithFormat:@"media/search?lat=%f&lng=%f",location.latitude,location.longitude] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


#pragma mark - Users -


- (void)getUserDetails:(NSString *)userId
           withSuccess:(void (^)(InstagramUser *userDetail))success
               failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/%@",userId]  parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			InstagramUser *userDetail = response;
			success(userDetail);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaForUser:(NSString *)userId
            withSuccess:(InstagramMediaBlock)success
                failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/%@/media/recent",userId] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaForUser:(NSString *)userId count:(NSInteger)count maxId:(NSString *)maxId
            withSuccess:(InstagramMediaBlock)success
                failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxId];
    [self getPath:[NSString stringWithFormat:@"users/%@/media/recent",userId] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)searchUsersWithString:(NSString *)string
               withSuccess:(void (^)(NSArray *users, InstagramPaginationInfo *paginationInfo))success
                   failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/search?q=%@",string] parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


#pragma mark - Self -


- (void)getSelfUserDetailsWithSuccess:(void (^)(InstagramUser *userDetail))success
                             failure:(InstagramFailureBlock)failure
{
    [self getPath:@"users/self" parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        InstagramUser *userDetail = response;
		if(success)
		{
			success(userDetail);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getSelfFeedWithSuccess:(InstagramMediaBlock)success
            failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/self/feed"] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getSelfFeedWithCount:(NSInteger)count maxId:(NSString *)maxId
                     success:(InstagramMediaBlock)success
                       failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxId];
    [self getPath:[NSString stringWithFormat:@"users/self/feed"] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaLikedBySelfWithSuccess:(InstagramMediaBlock)success
                        failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/self/media/liked"] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaLikedBySelfWithCount:(NSInteger)count maxId:(NSString *)maxId
                             success:(InstagramMediaBlock)success
                             failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxLikeId];
    [self getPath:[NSString stringWithFormat:@"users/self/media/liked"] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}

- (void)getSelfRecentMediaWithSuccess:(InstagramMediaBlock)success
							failure:(InstagramFailureBlock)failure
{
	[self getPath:[NSString stringWithFormat:@"users/self/media/recent"] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
		if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
	} failure:^(NSError *error, NSInteger statusCode) {
		if(failure)
		{
			failure(error);
		}
	}];
}


- (void)getSelfRecentMediaWithCount:(NSInteger)count maxId:(NSString *)maxId
								success:(InstagramMediaBlock)success
								failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxId];
	[self getPath:[NSString stringWithFormat:@"users/self/media/recent"] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
		if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
	} failure:^(NSError *error, NSInteger statusCode) {
		if(failure)
		{
			failure(error);
		}
	}];
}

#pragma mark - Tags -


- (void)getTagDetailsWithName:(NSString *)name
                  withSuccess:(void (^)(InstagramTag *tag))success
                      failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"tags/%@",name] parameters:nil responseModel:[InstagramTag class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			InstagramTag *tag = response;
			success(tag);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaWithTagName:(NSString *)tag
                withSuccess:(InstagramMediaBlock)success
                    failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"tags/%@/media/recent",tag] parameters:nil responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getMediaWithTagName:(NSString *)tag count:(NSInteger)count maxId:(NSString *)maxId
                withSuccess:(InstagramMediaBlock)success
                    failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxTagId];
    [self getPath:[NSString stringWithFormat:@"tags/%@/media/recent",tag] parameters:params responseModel:[InstagramMedia class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
		if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)searchTagsWithName:(NSString *)name
            withSuccess:(InstagramTagsBlock)success
                failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"tags/search?q=%@",name] parameters:nil responseModel:[InstagramTag class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)searchTagsWithName:(NSString *)name count:(NSInteger)count maxId:(NSString *)maxId
               withSuccess:(InstagramTagsBlock)success
                   failure:(InstagramFailureBlock)failure
{
    NSDictionary *params = [self parametersFromCount:count maxId:maxId andMaxIdType:kPaginationMaxId];
    [self getPath:[NSString stringWithFormat:@"tags/search?q=%@",name] parameters:params responseModel:[InstagramTag class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


#pragma mark - Comments -


- (void)getCommentsOnMedia:(NSString *)mediaId
               withSuccess:(InstagramCommentsBlock)success
                   failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"media/%@/comments",mediaId] parameters:nil responseModel:[InstagramComment class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)createComment:(NSString *)commentText
              onMedia:(NSString *)mediaId
          withSuccess:(void (^)(void))success
              failure:(InstagramFailureBlock)failure
{
    // Please email apidevelopers@instagram.com for access.
    NSDictionary *params = [NSDictionary dictionaryWithObjects:@[commentText] forKeys:@[kText]];
    [self postPath:[NSString stringWithFormat:@"media/%@/comments",mediaId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success();
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)removeComment:(NSString *)commentId
              onMedia:(NSString *)mediaId
          withSuccess:(void (^)(void))success
              failure:(InstagramFailureBlock)failure
{
    [self deletePath:[NSString stringWithFormat:@"media/%@/comments/%@",mediaId,commentId] parameters:nil responseModel:nil success:^{
        if(success)
		{
			success();
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


#pragma mark - Likes -


- (void)getLikesOnMedia:(NSString *)mediaId
            withSuccess:(void (^)(NSArray *likedUsers))success
                failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"media/%@/likes",mediaId] parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)likeMedia:(NSString *)mediaId
      withSuccess:(void (^)(void))success
          failure:(InstagramFailureBlock)failure
{
    [self postPath:[NSString stringWithFormat:@"media/%@/likes",mediaId] parameters:nil responseModel:nil success:^(NSDictionary *responseObject)
     {
         if(success)
         {
             success();
         }
     } failure:^(NSError *error, NSInteger statusCode) {
         if(failure)
         {
             failure(error);
         }
     }];
}


- (void)unlikeMedia:(NSString *)mediaId
        withSuccess:(void (^)(void))success
            failure:(InstagramFailureBlock)failure
{
    [self deletePath:[NSString stringWithFormat:@"media/%@/likes",mediaId] parameters:nil responseModel:nil success:^{
        if(success)
		{
			success();
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


#pragma mark - Relationships -


- (void)getRelationshipStatusOfUser:(NSString *)userId
                          withSuccess:(void (^)(NSDictionary *responseDictionary))success
                              failure:(void (^)(NSError* error))failure
{
    [self getPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:nil responseModel:[NSDictionary class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSDictionary *responseDictionary = response;
			success(responseDictionary);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getUsersFollowedByUser:(NSString *)userId
                   withSuccess:(InstagramObjectsBlock)success
                       failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/%@/follows",userId] parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getFollowersOfUser:(NSString *)userId
                   withSuccess:(InstagramObjectsBlock)success
                       failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/%@/followed-by",userId] parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)getFollowRequestsWithSuccess:(InstagramObjectsBlock)success
                   failure:(InstagramFailureBlock)failure
{
    [self getPath:[NSString stringWithFormat:@"users/self/requested-by"] parameters:nil responseModel:[InstagramUser class] success:^(id response, InstagramPaginationInfo *paginationInfo) {
        if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
        if(failure)
		{
			failure(error);
		}
    }];
}


- (void)followUser:(NSString *)userId
       withSuccess:(void (^)(NSDictionary *response))success
           failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionFollow};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


- (void)unfollowUser:(NSString *)userId
       withSuccess:(void (^)(NSDictionary *response))success
           failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionUnfollow};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


- (void)blockUser:(NSString *)userId
       withSuccess:(void (^)(NSDictionary *response))success
           failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionBlock};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


- (void)unblockUser:(NSString *)userId
         withSuccess:(void (^)(NSDictionary *response))success
             failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionUnblock};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


- (void)approveUser:(NSString *)userId
      withSuccess:(void (^)(NSDictionary *response))success
          failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionApprove};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject)
    {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


- (void)denyUser:(NSString *)userId
        withSuccess:(void (^)(NSDictionary *response))success
            failure:(void (^)(NSError* error))failure
{
    NSDictionary *params = @{kRelationshipActionKey:kRelationshipActionDeny};
    [self postPath:[NSString stringWithFormat:@"users/%@/relationship",userId] parameters:params responseModel:nil success:^(NSDictionary *responseObject) {
        if(success)
		{
			success(responseObject);
		}
    } failure:^(NSError *error, NSInteger statusCode) {
                if(failure)
		{
			failure(error);
		}
        NSLog(@"%@", [error description]);
    }];
}


#pragma mark - Pagination -


- (void)getPaginatedItemsForInfo:(InstagramPaginationInfo *)paginationInfo
                     withSuccess:(void (^)(NSArray *objects, InstagramPaginationInfo *paginationInfo))success
                         failure:(InstagramFailureBlock)failure
{
    NSString *relativePath = [[paginationInfo.nextURL absoluteString] stringByReplacingOccurrencesOfString:[self.httpManager.baseURL absoluteString] withString:@""];
    [self getPath:relativePath parameters:nil responseModel:paginationInfo.type success:^(id response, InstagramPaginationInfo *paginationInfo) {
        
		if(success)
		{
			NSArray *objects = response;
			success(objects, paginationInfo);
		}
		
    } failure:^(NSError *error, NSInteger statusCode) {
        
		if(failure)
		{
			failure(error);
		}
		
    }];
}

@end
