#import "AwemeHeaders.h"
#import "DYYYPrivacyRecordUploadGuard.h"
#import "DYYYUtils.h"

// 抖音 39.1.0 访问他人主页时会由详情组件直接上传访客记录
%hook AWEProfileUserDetailComponent

- (void)reportUserDetailVisitIfNeeded:(id)user {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

// 兼容旧版访客记录上传路径
%hook AWEProfileRecordHelper

+ (void)postProfileRecordWithParams:(id)params {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithParams:(id)params completionBlock:(id)completionBlock {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithKey:(id)key valueDic:(id)valueDic {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

+ (void)postProfileRecordWithKey:(id)key valueDic:(id)valueDic completionBlock:(id)completionBlock {
    if ([DYYYPrivacyRecordUploadGuard isProfileVisitRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

// 抖音 39.7.0：作品浏览记录由 AFDPlayerAndInteractionService 上报至
// /aweme/v1/familiar/video/stats/（scene 常见值 FeedVideoViewedDedicatedStats）
%hook AFDPlayerAndInteractionService

- (void)statisticsVideoViewedWithID:(NSString *)itemID scene:(NSString *)scene {
    if ([DYYYPrivacyRecordUploadGuard isAwemeViewRecordUploadDisabled]) {
        return;
    }

    %orig;
}

- (void)statisticsVideoViewedWithID:(NSString *)itemID
                           authorID:(NSString *)authorID
                       followStatus:(long long)followStatus
                     followerStatus:(long long)followerStatus
                            isStory:(BOOL)isStory
                  isRequestDirectly:(BOOL)isRequestDirectly
                              scene:(NSString *)scene {
    if ([DYYYPrivacyRecordUploadGuard isAwemeViewRecordUploadDisabled]) {
        return;
    }

    %orig;
}

%end

static BOOL DYYYTryBlockPrivacyNetworkRequest(NSString *URLString, id completion) {
    if (![DYYYPrivacyRecordUploadGuard shouldBlockURLString:URLString]) {
        return NO;
    }

    [DYYYPrivacyRecordUploadGuard invokeCancelledCompletionIfPossible:completion];
    return YES;
}

%hook AWENetworkService

+ (id)postWithURLString:(NSString *)URLString params:(id)params completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

+ (id)getWithURLString:(NSString *)URLString params:(id)params completion:(id)completion {
    if (DYYYTryBlockPrivacyNetworkRequest(URLString, completion)) {
        return nil;
    }
    return %orig;
}

// 41.3 实测：带 headerField 的旧签名网络入口、以及
// requestWithURLString:params:method:completion: 在二进制里均不存在。
// 现行入口只有 postWithURLString:params:completion: 和
// getWithURLString:params:completion:（上面已 hook）。
// 这些裸 hook 挂不上、只让统计虚高，移除。

%end

// ===== 41.3 网络拦截探测（临时探针，只读不改行为）=====
//
// TTNetworkManager 的三个 requestFor* 入口已被删除，改成过滤器注册机制。
// 二进制只能证明「这些方法收一个 block」（类型编码 v24@0:8@?16），
// 拿不到 block 自己的参数表，所以无法写真正的拦截判断。
//
// 这里挂只读探针：注册时把 block 的完整签名打进日志。
// 签名来自 Block_descriptor->signature（见 DYYYUtils blockSignature:），
// 只读字符串，不执行 block、不改任何返回值，也不会让抖音崩溃。
//
// 探针不做开关门控：只在过滤器注册时触发，一个进程内同类签名最多打一次，
// 日志量极小。这样不需要新增设置项，装上就能采到数据。
// 探测完成、换成真正的拦截实现后，这一整块应当删除。
static void DYYYProbeNetworkFilterBlock(NSString *api, id block) {
    NSString *signature = [DYYYUtils blockSignature:block];
    NSString *key = [NSString stringWithFormat:@"%@|%@", api, signature ?: @"(无签名)"];

    static NSMutableSet<NSString *> *loggedKeys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggedKeys = [NSMutableSet set];
    });

    BOOL isNew = NO;
    @synchronized (loggedKeys) {
        if (![loggedKeys containsObject:key]) {
            [loggedKeys addObject:key];
            isNew = YES;
        }
    }
    if (!isNew) {
        return;
    }

    NSLog(@"[DYYY][net-probe] %@ signature=%@", api, signature ?: @"(无签名)");
}

%hook TTNetworkManager

- (void)addRequestFilterBlock:(id)block {
    DYYYProbeNetworkFilterBlock(@"addRequestFilterBlock:", block);
    %orig;
}

- (void)addResponseFilterBlock:(id)block {
    DYYYProbeNetworkFilterBlock(@"addResponseFilterBlock:", block);
    %orig;
}

- (BOOL)addPreRequestFilterObject:(id)object {
    DYYYProbeNetworkFilterBlock(@"addPreRequestFilterObject:", object);
    return %orig;
}

- (BOOL)addRequestFilterObject:(id)object {
    DYYYProbeNetworkFilterBlock(@"addRequestFilterObject:", object);
    return %orig;
}

- (BOOL)addResponseFilterObject:(id)object {
    DYYYProbeNetworkFilterBlock(@"addResponseFilterObject:", object);
    return %orig;
}

// 41.3 实测：以下三个 request 入口在二进制里已全部不存在。
// TTNetworkManager 现在的请求入口换成了过滤器机制：
//   addRequestFilterBlock: / addResponseFilterBlock:
//   addPreRequestFilterObject: / addRequestFilterObject: / addResponseFilterObject:
//   setEnableReqFilter: / enableApiHttpIntercept
// 其中 addRequestFilterBlock: 的类型编码是 v24@0:8@?16 —— 只知道收一个 block，
// 拿不到 block 自身的参数表，离线无法确定签名，需要真机探测后才能重新适配。
//
// 这段保留是为了留住原有判断逻辑（URL 匹配 + 回调拦截）作为适配时的参考，
// 它挂不上任何方法，不会影响运行；要恢复隐私网络拦截需另立一项重做。

- (id)requestForJSONWithURL:(NSString *)url
                     params:(id)params
                     method:(NSString *)method
           needCommonParams:(BOOL)needCommonParams
                headerField:(id)headerField
          requestSerializer:(Class)requestSerializerClass
         responseSerializer:(Class)responseSerializerClass
                 autoResume:(BOOL)autoResume
                   callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

- (id)requestForJSONWithResponse:(NSString *)url
                          params:(id)params
                          method:(NSString *)method
                needCommonParams:(BOOL)needCommonParams
                     headerField:(id)headerField
               requestSerializer:(Class)requestSerializerClass
              responseSerializer:(Class)responseSerializerClass
                      autoResume:(BOOL)autoResume
                        callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

- (id)requestForBinaryWithResponse:(NSString *)url
                            params:(id)params
                            method:(NSString *)method
                  needCommonParams:(BOOL)needCommonParams
                       headerField:(id)headerField
                          callback:(id)callback {
    if (DYYYTryBlockPrivacyNetworkRequest(url, callback)) {
        return nil;
    }
    return %orig;
}

%end

static BOOL DYYYShouldSkipPrivacyRecordTaskStart(id task) {
    BOOL shouldBlock = [DYYYPrivacyRecordUploadGuard isTaskMarkedForBlocking:task] ||
                       [DYYYPrivacyRecordUploadGuard shouldBlockRequestObject:task];
    if (!shouldBlock) {
        return NO;
    }

    // 即使任务对象不支持 cancel，也必须阻止原始启动，避免隐私请求继续发出。
    (void)[DYYYPrivacyRecordUploadGuard cancelTaskIfPossible:task];
    return YES;
}

%hook TTHttpTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook TTHttpTaskChromium

- (void)runRequestFiltersAndStart {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook TTConcurrentHttpTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook NSURLSessionTask

- (void)resume {
    if (DYYYShouldSkipPrivacyRecordTaskStart(self)) {
        return;
    }

    %orig;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDataTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithURL:(NSURL *)url completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:url];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionDownloadTask *)downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL *location, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionDownloadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromData:(NSData *)bodyData completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithRequest:(NSURLRequest *)request fromFile:(NSURL *)fileURL completionHandler:(void (^)(NSData *data, NSURLResponse *response, NSError *error))completionHandler {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

- (NSURLSessionUploadTask *)uploadTaskWithStreamedRequest:(NSURLRequest *)request {
    NSURLSessionUploadTask *task = %orig;
    [DYYYPrivacyRecordUploadGuard markTaskForBlockingIfNeeded:task requestObject:request];
    return task;
}

%end

