# Uncomment this line to define a global platform for your project

abstract_target 'MatrixSDK' do
    
    pod 'AFNetworking', '~> 4.0.0'
    pod 'GZIP', '~> 1.3.0'

    pod 'SwiftyBeaver', '1.9.5'
    
    pod 'OLMKit', '~> 3.2.5', :inhibit_warnings => true
    #pod 'OLMKit', :path => '../olm/OLMKit.podspec'
    
    pod 'Realm', '10.16.0'
    pod 'libbase58', '~> 0.1.4'
    
    target 'MatrixSDK-iOS' do
        platform :ios, '9.0'
        
        target 'MatrixSDKTests-iOS' do
            inherit! :search_paths
            pod 'OHHTTPStubs', '~> 9.1.0'
        end
    end
    
    target 'MatrixSDK-macOS' do
        platform :osx, '10.10'

        target 'MatrixSDKTests-macOS' do
            inherit! :search_paths
            pod 'OHHTTPStubs', '~> 9.1.0'
        end
    end
end

# https://github.com/matrix-org/matrix-ios-sdk/issues/804#issuecomment-656611365
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '10.0'
    end
  end
end
