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

@end
