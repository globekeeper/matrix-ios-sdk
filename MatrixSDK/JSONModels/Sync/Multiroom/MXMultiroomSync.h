//
//  MXMultiroomSync.h
//  MatrixSDK
//
//  Created by Artem Krachulov on 04.04.2023.
//

#import <MatrixSDK/MatrixSDK.h>

@class MXMultiroomSyncLocation;

NS_ASSUME_NONNULL_BEGIN

@interface MXMultiroomSync : MXJSONModel

/**
 The location posted via /_matrix/client/r0/multiroom/connect.multiroom.location request.
 
 More info https://www.notion.so/globekeeper/Matrix-multiroom-710e53ddef064dd2bd461a94e7ae75d8?pvs=4#245866898f5b4104833bcc8415a03268
 */
@property (nonatomic) MXMultiroomSyncLocation *location;

/**
 Unimplemented
 */
@property (nonatomic) MXMultiroomSyncLocation *panic;

@end

NS_ASSUME_NONNULL_END
