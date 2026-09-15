#!/usr/bin/env python3
"""Regenerate the small Xcode project without third-party project tooling."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


def obj(name, body):
    objects[uid(name)] = body
    return uid(name)


def q(value):
    return json.dumps(value)


def array(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'


def settings(values):
    return '{' + ' '.join(f'{k} = {q(v)};' for k, v in values.items()) + '}'


def configs(name, values):
    ids = []
    for kind in ['Debug', 'Release']:
        config = dict(values)
        config['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if kind == 'Debug' else '-O'
        config['DEBUG_INFORMATION_FORMAT'] = 'dwarf' if kind == 'Debug' else 'dwarf-with-dsym'
        config['ONLY_ACTIVE_ARCH'] = 'YES' if kind == 'Debug' else 'NO'
        if kind == 'Debug':
            config['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
            config['ENABLE_TESTABILITY'] = 'YES'
        ids.append(obj(name + kind, f'isa = XCBuildConfiguration; buildSettings = {settings(config)}; name = {kind};'))
    return obj(name + 'Configs', f'isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')


app_refs, app_sources, app_resources, test_refs, test_sources = [], [], [], [], []
paths = sorted((ROOT / 'PlayScript').rglob('*.swift'))
paths += [ROOT / 'PlayScript/Resources/Assets.xcassets', ROOT / 'PlayScript/Resources/PrivacyInfo.xcprivacy']
paths += sorted((ROOT / 'PlayScript/Resources/Audio').glob('*.wav'))
paths += sorted((ROOT / 'PlayScript/Resources/Animations').glob('*.json'))
paths += sorted((ROOT / 'PlayScriptUITests').glob('*.swift'))
for path in paths:
    rel = str(path.relative_to(ROOT))
    file_type = {'.swift': 'sourcecode.swift', '.wav': 'audio.wav', '.json': 'text.json', '.xcassets': 'folder.assetcatalog', '.xcprivacy': 'text.xml'}[path.suffix]
    ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {file_type}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    build = obj(rel + 'Build', f'isa = PBXBuildFile; fileRef = {ref};')
    if rel.startswith('PlayScriptUITests/'):
        test_refs.append(ref)
        test_sources.append(build)
    else:
        app_refs.append(ref)
        (app_sources if path.suffix == '.swift' else app_resources).append(build)

app_product = obj('AppProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = PlayScript.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = obj('TestProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = PlayScriptUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('Products', f'isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = "<group>";')
app_group = obj('AppGroup', f'isa = PBXGroup; children = {array(app_refs)}; name = PlayScript; sourceTree = "<group>";')
test_group = obj('TestGroup', f'isa = PBXGroup; children = {array(test_refs)}; name = PlayScriptUITests; sourceTree = "<group>";')
main_group = obj('MainGroup', f'isa = PBXGroup; children = {array([app_group, test_group, products])}; sourceTree = "<group>";')
package = obj('CorePackage', 'isa = XCLocalSwiftPackageReference; relativePath = StoryCore;')
package_product = obj('CoreProduct', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = StoryCore;')
package_build = obj('CoreBuild', f'isa = PBXBuildFile; productRef = {package_product};')
lottie_package = obj('LottiePackage', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/airbnb/lottie-spm.git"; requirement = { kind = upToNextMajorVersion; minimumVersion = 4.6.1; };')
lottie_product = obj('LottieProduct', f'isa = XCSwiftPackageProductDependency; package = {lottie_package}; productName = Lottie;')
lottie_build = obj('LottieBuild', f'isa = PBXBuildFile; productRef = {lottie_product};')


def phase(name, kind, files):
    return obj(name, f'isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = {array(files)}; runOnlyForDeploymentPostprocessing = 0;')


app_phases = [phase('AppSources', 'Sources', app_sources), phase('AppFrameworks', 'Frameworks', [package_build, lottie_build]), phase('AppResources', 'Resources', app_resources)]
test_phases = [phase('TestSources', 'Sources', test_sources), phase('TestFrameworks', 'Frameworks', []), phase('TestResources', 'Resources', [])]
common = {
    'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'SWIFT_VERSION': '5.0',
    'CLANG_ENABLE_MODULES': 'YES', 'SDKROOT': 'iphoneos',
    'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'CODE_SIGN_STYLE': 'Automatic',
    'TARGETED_DEVICE_FAMILY': '1', 'GENERATE_INFOPLIST_FILE': 'YES',
    'MARKETING_VERSION': '1.0', 'CURRENT_PROJECT_VERSION': '1',
    'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
}
app_config = configs('App', common | {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.sh1vendra.PlayScript', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'INFOPLIST_KEY_CFBundleDisplayName': 'PlayScript', 'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.books',
    'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations': 'UIInterfaceOrientationPortrait',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES',
    'INFOPLIST_KEY_UIStatusBarStyle': 'UIStatusBarStyleDefault',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor',
    'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
    'SUPPORTS_MACCATALYST': 'NO', 'SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD': 'NO',
})
test_config = configs('Tests', common | {
    'PRODUCT_BUNDLE_IDENTIFIER': 'com.sh1vendra.PlayScriptUITests', 'PRODUCT_NAME': '$(TARGET_NAME)',
    'TEST_TARGET_NAME': 'PlayScript',
})
project_config = configs('Project', {'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '18.0'})
app_target = obj('AppTarget', f'isa = PBXNativeTarget; buildConfigurationList = {app_config}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = PlayScript; packageProductDependencies = {array([package_product, lottie_product])}; productName = PlayScript; productReference = {app_product}; productType = "com.apple.product-type.application";')
proxy = obj('AppProxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("Project")}; proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = PlayScript;')
dependency = obj('AppDependency', f'isa = PBXTargetDependency; target = {app_target}; targetProxy = {proxy};')
test_target = obj('TestTarget', f'isa = PBXNativeTarget; buildConfigurationList = {test_config}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = {array([dependency])}; name = PlayScriptUITests; productName = PlayScriptUITests; productReference = {test_product}; productType = "com.apple.product-type.bundle.ui-testing";')
obj('Project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {app_target} = {{CreatedOnToolsVersion = 16.0;}}; {test_target} = {{CreatedOnToolsVersion = 16.0; TestTargetID = {app_target};}}; }}; }}; buildConfigurationList = {project_config}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = {array([package, lottie_package])}; targets = {array([app_target, test_target])};')

project = ROOT / 'PlayScript.xcodeproj'
project.mkdir(exist_ok=True)
lines = '\n'.join(f'\t\t{key} = {{ {body} }};' for key, body in objects.items())
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + lines + '\n\t};\n\trootObject = ' + uid('Project') + ';\n}\n')


def reference(target, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:PlayScript.xcodeproj"/>'


scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app_target, 'PlayScript.app')}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test_target, 'PlayScriptUITests.xctest')}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target, 'PlayScript.app')}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app_target, 'PlayScript.app')}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
scheme_dir = project / 'xcshareddata/xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'PlayScript.xcscheme').write_text(scheme)
print('Generated PlayScript.xcodeproj')
