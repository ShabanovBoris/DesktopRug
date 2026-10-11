#!/usr/bin/env python3
"""Generate the dependency-free Xcode project from the checked-in source tree."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
version = (root / 'VERSION').read_text().strip()
project = root / 'DesktopRug.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}

def identifier(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def add(name, value):
    key = identifier(name)
    objects[key] = value
    return key

def quote(value):
    return json.dumps(value)

def array(values):
    return '(' + ', '.join(values) + (',)' if values else ')')

def file(path, kind):
    return add('file:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;')

swift = sorted(p.relative_to(root).as_posix() for p in (root / 'DesktopRug').rglob('*.swift'))
core = [p for p in swift if '/Core/' in p]
test = sorted(p.relative_to(root).as_posix() for p in (root / 'DesktopRugTests').glob('*.swift'))
shaders = sorted(p.relative_to(root).as_posix() for p in (root / 'DesktopRug/Rendering').glob('*.metal'))
resources = ['DesktopRug/Resources/heriz.png', 'DesktopRug/Resources/indigo.png', 'DesktopRug/Resources/soviet-red.png', 'DesktopRug/Resources/soviet-floral.png', 'DesktopRug/Resources/Assets.xcassets', 'LICENSE', 'DesktopRug/Resources/TextureSources.md']
refs = {p: file(p, 'sourcecode.swift' if p.endswith('.swift') else 'sourcecode.metal') for p in sorted(set(swift + test + shaders))}
for p in resources:
    refs[p] = file(p, 'folder.assetcatalog' if p.endswith('xcassets') else 'image.png' if p.endswith('.png') else 'text')
for p in ['DesktopRug/Info.plist', 'DesktopRug/DesktopRug.entitlements']:
    refs[p] = file(p, 'text.plist.xml')

def phase(name, isa, paths):
    builds = [add(name + ':' + p, f'isa = PBXBuildFile; fileRef = {refs[p]};') for p in paths]
    return add(name, f'isa = {isa}; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')

def configs(name, extra):
    common = {'SDKROOT': 'macosx', 'MACOSX_DEPLOYMENT_TARGET': '14.0', 'SWIFT_VERSION': '5.0', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'CODE_SIGN_IDENTITY': '-', 'CODE_SIGN_STYLE': 'Manual', 'ENABLE_USER_SCRIPT_SANDBOXING': 'YES'}
    result = []
    for mode in ['Debug', 'Release']:
        settings = dict(common, **extra)
        settings.update({'SWIFT_OPTIMIZATION_LEVEL': '-O' if mode == 'Release' else '-Onone', 'SWIFT_COMPILATION_MODE': 'wholemodule' if mode == 'Release' else 'incremental', 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym' if mode == 'Release' else 'dwarf', 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG' if mode == 'Debug' else '', 'ENABLE_TESTABILITY': 'YES' if mode == 'Debug' else 'NO', 'MTL_FAST_MATH': 'YES', 'MTL_ENABLE_DEBUG_INFO': 'INCLUDE_SOURCE' if mode == 'Debug' else 'NO'})
        values = ' '.join(f'{k} = {quote(v)};' for k, v in settings.items())
        result.append(add(name + ':' + mode, f'isa = XCBuildConfiguration; buildSettings = {{{values}}}; name = {mode};'))
    return add(name + ':configs', f'isa = XCConfigurationList; buildConfigurations = {array(result)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Desktop Rug.app"; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = DesktopRugTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
app_settings = configs('app', {'PRODUCT_NAME': 'Desktop Rug', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.desktoprug.app', 'INFOPLIST_FILE': 'DesktopRug/Info.plist', 'CODE_SIGN_ENTITLEMENTS': 'DesktopRug/DesktopRug.entitlements', 'ENABLE_HARDENED_RUNTIME': 'YES', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': version, 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks', 'SWIFT_EMIT_LOC_STRINGS': 'NO'})
test_settings = configs('tests', {'PRODUCT_NAME': 'DesktopRugTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'dev.desktoprug.tests', 'GENERATE_INFOPLIST_FILE': 'YES', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @loader_path/../Frameworks @executable_path/../Frameworks', 'ENABLE_HARDENED_RUNTIME': 'NO'})
app_phases = [phase('app-sources', 'PBXSourcesBuildPhase', swift + shaders), phase('app-resources', 'PBXResourcesBuildPhase', resources), phase('app-frameworks', 'PBXFrameworksBuildPhase', [])]
test_phases = [phase('test-sources', 'PBXSourcesBuildPhase', core + test), phase('test-resources', 'PBXResourcesBuildPhase', []), phase('test-frameworks', 'PBXFrameworksBuildPhase', [])]
app = add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_settings}; buildPhases = {array(app_phases)}; buildRules = (); dependencies = (); name = DesktopRug; productName = "Desktop Rug"; productReference = {app_product}; productType = "com.apple.product-type.application";')
tests = add('test-target', f'isa = PBXNativeTarget; buildConfigurationList = {test_settings}; buildPhases = {array(test_phases)}; buildRules = (); dependencies = (); name = DesktopRugTests; productName = DesktopRugTests; productReference = {test_product}; productType = "com.apple.product-type.bundle.unit-test";')
groups = []
for name, paths in [('Application', [p for p in swift if p not in core] + shaders), ('Core', core), ('Tests', test), ('Resources', resources + ['DesktopRug/Info.plist', 'DesktopRug/DesktopRug.entitlements'])]:
    groups.append(add('group:' + name, f'isa = PBXGroup; children = {array([refs[p] for p in paths])}; name = {quote(name)}; sourceTree = "<group>";'))
products = add('products', f'isa = PBXGroup; children = {array([app_product, test_product])}; name = Products; sourceTree = "<group>";')
main = add('main-group', f'isa = PBXGroup; children = {array(groups + [products])}; sourceTree = "<group>";')
project_configs = configs('project', {})
project_id = add('project', f'isa = PBXProject; attributes = {{LastUpgradeCheck = 2640; LastSwiftUpdateCheck = 2640;}}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([app, tests])};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{key} = {{ {value} }};' for key, value in objects.items())
text += f'\n}}; rootObject = {project_id}; }}\n'
(project / 'project.pbxproj').write_text(text)
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
def reference(target, product, name):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:DesktopRug.xcodeproj"/>'
app_ref = reference(app, 'Desktop Rug.app', 'DesktopRug')
test_ref = reference(tests, 'DesktopRugTests.xctest', 'DesktopRugTests')
(schemes / 'DesktopRug.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2640" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{test_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project.name}: {len(swift)} Swift files, {len(shaders)} Metal files, {len(test)} test files.')
