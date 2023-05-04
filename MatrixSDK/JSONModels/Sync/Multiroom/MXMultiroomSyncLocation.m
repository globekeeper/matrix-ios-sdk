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
    MXJSONModelSetDictionary(multiroomSyncLocation.content, JSONDictionary[@"content"]);
    MXJSONModelSetUInt64(multiroomSyncLocation.originServerTs, JSONDictionary[@"origin_server_ts"]);
  }
  
  return multiroomSyncLocation;
}

- (NSDictionary *)JSONDictionary
{
  NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
  if (JSONDictionary)
  {
    JSONDictionary[@"content"] = _content;
    JSONDictionary[@"origin_server_ts"] = @(_originServerTs);
  }
  
  return JSONDictionary;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
  self = [super init];
  if (self)
  {
    _content = [aDecoder decodeObjectForKey:@"content"];
    _originServerTs = (uint64_t)[aDecoder decodeInt64ForKey:@"originServerTs"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
  if(_content) {
    [aCoder encodeObject:_content forKey:@"content"];
  }
  if (_originServerTs) {
    [aCoder encodeInt64:(int64_t)_originServerTs forKey:@"originServerTs"];
  }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  MXMultiroomSyncLocation *multiroomSyncLocation = [[[self class] allocWithZone:zone] init];
  
  multiroomSyncLocation->_content = [_content copyWithZone:zone];
  multiroomSyncLocation.originServerTs = _originServerTs;
  return multiroomSyncLocation;
}

@end
