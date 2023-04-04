//
//  MXMultiroomSyncLocation.m
//  MatrixSDK
//
//  Created by Artem Krachulov on 04.04.2023.
//

#import "MXMultiroomSyncLocation.h"

@implementation MXMultiroomSyncLocation

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
  MXMultiroomSyncLocation *multiroomSyncLocation = [[MXMultiroomSyncLocation alloc] init];
  if (multiroomSyncLocation)
  {
    MXJSONModelSetDictionary(multiroomSyncLocation.wireContent, JSONDictionary[@"content"]);
    MXJSONModelSetUInt64(multiroomSyncLocation.originServerTs, JSONDictionary[@"origin_server_ts"]);
  }
  
  return multiroomSyncLocation;
}

- (NSDictionary *)JSONDictionary
{
  NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
  if (JSONDictionary)
  {
    JSONDictionary[@"content"] = _wireContent;
    JSONDictionary[@"origin_server_ts"] = @(_originServerTs);
  }
  
  return JSONDictionary;
}

@end
