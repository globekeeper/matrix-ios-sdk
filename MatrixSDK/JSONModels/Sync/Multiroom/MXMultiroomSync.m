//
//  MXMultiroomSync.m
//  MatrixSDK
//
//  Created by Artem Krachulov on 04.04.2023.
//

#import "MXMultiroomSync.h"
#import "MXMultiroomSyncLocation.h"

@implementation MXMultiroomSync

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
  MXMultiroomSync *multiroomSync = [[MXMultiroomSync alloc] init];
  if (multiroomSync)
  {
    MXJSONModelSetMXJSONModel(multiroomSync.location, MXMultiroomSyncLocation, JSONDictionary[@"connect.multiroom.location"]);
    MXJSONModelSetMXJSONModel(multiroomSync.panic, MXMultiroomSyncLocation, JSONDictionary[@"connect.multiroom.panic"]);
  }
  
  return multiroomSync;
}

- (NSDictionary *)JSONDictionary
{
  NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

  if (self.location)
  {
    JSONDictionary[@"connect.multiroom.location"] = self.location.JSONDictionary;
  }
  if (self.panic)
  {
    JSONDictionary[@"connect.multiroom.panic"] = self.panic.JSONDictionary;
  }
  
  return JSONDictionary;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
  self = [super init];
  if (self)
  {
    _location = [aDecoder decodeObjectForKey:@"location"];
    _panic = [aDecoder decodeObjectForKey:@"panic"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
  if(_location) {
    [aCoder encodeObject:_location forKey:@"location"];
  }
  if (_panic) {
    [aCoder encodeObject:_panic forKey:@"panic"];
  }
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  MXMultiroomSync *multiroomSync = [[[self class] allocWithZone:zone] init];
  
  multiroomSync->_location = [_location copyWithZone:zone];
  multiroomSync->_panic = [_panic copyWithZone:zone];
  return multiroomSync;
}

@end
