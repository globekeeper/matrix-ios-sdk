// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#ifndef MXOlmKitInterface_h
#define MXOlmKitInterface_h

/**
 `OLMKitPickleKeyDelegate` provides the key to use for every pickle operation.
 */
@protocol OLMKitPickleKeyDelegate <NSObject>

- (NSData*)pickleKey;

@end

@interface OLMKit : NSObject

/// Project version string for OLMKit, the same as libolm.
+ (NSString*)versionString;

/// The optional delegate that provides the pickle key.
/// If not provided, OLMKit will use default pickle keys.
@property (nonatomic, weak, nullable) id<OLMKitPickleKeyDelegate> pickleKeyDelegate;

/// The singleton instance.
+ (instancetype)sharedInstance;

@end

#endif /* MXOlmKitInterface_h */
