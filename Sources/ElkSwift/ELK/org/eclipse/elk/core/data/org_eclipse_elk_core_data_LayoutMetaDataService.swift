// Copyright (c) 2008, 2020 Kiel University and others.
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0.
//
// SPDX-License-Identifier: EPL-2.0

import Foundation
import os

// MARK: - Supporting Types

/// Simple triple for storing dependency/support data
package class DependencyTriple {
    package var firstId: String = ""
    package var secondId: String = ""
    package var value: Any?
    package init() {}
}

// MARK: - Main Service

package final class LayoutMetaDataService {
    private nonisolated(unsafe) static var _instance: LayoutMetaDataService?
    private static let _lock: os_unfair_lock_t = {
        let lock = os_unfair_lock_t.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        return lock
    }()

    /// Thread-safe access to the singleton. Auto-initializes on first access.
    package static var instance: LayoutMetaDataService {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        if let inst = _instance { return inst }
        let inst = LayoutMetaDataService()
        _instance = inst
        return inst
    }

    package var layoutAlgorithmMap = [String: LayoutAlgorithmData]()
    package var layoutOptionMap = [String: LayoutOptionData]()
    package var legacyLayoutOptionMap = [String: LayoutOptionData]()
    package var layoutCategoryMap = [String: LayoutCategoryData]()
    package var algorithmSuffixMap = [String: LayoutAlgorithmData]()
    package var optionSuffixMap = [String: LayoutOptionData]()

    private init() {
        LayoutMetaDataService.initElkReflect()
    }

    package static func getInstance(loader: Any? = nil) -> LayoutMetaDataService {
        return instance
    }

    package static func unload() {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        _instance = nil
    }

    package static func initElkReflect() {
        // Register types with ElkReflect for property cloning support
        // Uses the (type, newFun:, cloneFun:) signature from ElkReflect
    }

    package func registerLayoutMetaDataProviders(_ providers: ILayoutMetaDataProvider...) {
        for provider in providers {
            let registry = Registry()
            registry.service = self
            provider.apply(registry)
            registry.applyDependencies()
        }
        optionSuffixMap.removeAll()
    }

    package func getAlgorithmData(_ id: String) -> LayoutAlgorithmData? {
        return layoutAlgorithmMap[id]
    }

    package func getAlgorithmData() -> [LayoutAlgorithmData] {
        return Array(layoutAlgorithmMap.values)
    }

    package func getAlgorithmData(by suffix: String) -> LayoutAlgorithmData? {
        guard !suffix.isEmpty else { return nil }
        if let data = algorithmSuffixMap[suffix] {
            return data
        }

        var data: LayoutAlgorithmData?
        for d in layoutAlgorithmMap.values {
            let id = d.getId()
            if id.hasSuffix(suffix) && (suffix.count == id.count || id[id.index(id.endIndex, offsetBy: -suffix.count - 1)] == ".") {
                if data != nil {
                    return nil
                }
                data = d
            }
        }

        if let found = data {
            algorithmSuffixMap[suffix] = found
        }

        return data
    }

    /// Alias for callers using the old name
    package func getAlgorithmDataBySuffix(_ suffix: String?) -> LayoutAlgorithmData? {
        guard let suffix = suffix else { return nil }
        return getAlgorithmData(by: suffix)
    }

    package func getAlgorithmData(bySuffixOrDefault algorithmId: String?, defaultId: String?) -> LayoutAlgorithmData? {
        if let algorithmId = algorithmId, !algorithmId.trimmingCharacters(in: .whitespaces).isEmpty {
            if let data = getAlgorithmData(by: algorithmId) {
                return data
            }
        }

        if let defaultId = defaultId, !defaultId.trimmingCharacters(in: .whitespaces).isEmpty {
            if let data = getAlgorithmData(by: defaultId) {
                return data
            }
        }

        return nil
    }

    /// Alias for callers using old name
    package func getAlgorithmDataBySuffixOrDefault(_ suffix: String?, _ defaultID: String?) -> LayoutAlgorithmData? {
        return getAlgorithmData(bySuffixOrDefault: suffix, defaultId: defaultID)
    }

    package func getOptionData(_ id: String) -> LayoutOptionData? {
        if let data = layoutOptionMap[id] {
            return data
        }
        return legacyLayoutOptionMap[id]
    }

    package func getOptionData() -> [LayoutOptionData] {
        return Array(layoutOptionMap.values)
    }

    package func getOptionData(by suffix: String) -> LayoutOptionData? {
        guard !suffix.isEmpty else { return nil }
        if let data = optionSuffixMap[suffix] {
            return data
        }

        var data: LayoutOptionData?

        for d in layoutOptionMap.values {
            let id = d.id
            if id.hasSuffix(suffix) && (suffix.count == id.count || id[id.index(id.endIndex, offsetBy: -suffix.count - 1)] == ".") {
                if data != nil {
                    return nil
                }
                data = d
            }
        }

        if data == nil {
            for d in layoutOptionMap.values {
                if let legacyIds = d.getLegacyIds() {
                    for id in legacyIds {
                        if id.hasSuffix(suffix) && (suffix.count == id.count || id[id.index(id.endIndex, offsetBy: -suffix.count - 1)] == ".") {
                            if data != nil {
                                return nil
                            }
                            data = d
                        }
                    }
                }
            }
        }

        if let found = data {
            optionSuffixMap[suffix] = found
        }

        return data
    }

    /// Alias for callers using bySuffix: label
    package func getOptionData(bySuffix suffix: String) -> LayoutOptionData? {
        return getOptionData(by: suffix)
    }

    package func getOptionData(for algorithm: LayoutAlgorithmData, targetType: LayoutOptionData.Target) -> [LayoutOptionData] {
        var result = [LayoutOptionData]()
        for option in layoutOptionMap.values {
            if algorithm.knowsOption(option.id) || CoreOptions.ALGORITHM.id == option.id {
                if option.getTargets().contains(targetType) {
                    result.append(option)
                }
            }
        }
        return result
    }

    package func getCategoryData(_ id: String) -> LayoutCategoryData? {
        return layoutCategoryMap[id]
    }

    package func getCategoryData() -> [LayoutCategoryData] {
        return Array(layoutCategoryMap.values)
    }

    // MARK: - Registry

    package class Registry: ILayoutMetaDataProvider_Registry {

        package weak var service: LayoutMetaDataService?

        package var optionDependencies = [DependencyTriple]()
        package var optionSupport = [DependencyTriple]()

        package init() {}

        package func register(_ algorithmData: LayoutAlgorithmData) {
            service?.layoutAlgorithmMap[algorithmData.id] = algorithmData
        }

        package func register(_ optionData: LayoutOptionData) {
            service?.layoutOptionMap[optionData.id] = optionData
            if let legacyIds = optionData.getLegacyIds() {
                for legacyId in legacyIds {
                    service?.legacyLayoutOptionMap[legacyId] = optionData
                }
            }
        }

        package func register(_ categoryData: LayoutCategoryData) {
            service?.layoutCategoryMap[categoryData.id] = categoryData
        }

        package func addDependency(_ sourceOption: String, _ targetOption: String, _ requiredValue: Any?) {
            let triple = DependencyTriple()
            triple.firstId = sourceOption
            triple.secondId = targetOption
            triple.value = requiredValue
            optionDependencies.append(triple)
        }

        package func addOptionSupport(_ algorithm: String, _ option: String, _ defaultValue: Any?) {
            let triple = DependencyTriple()
            triple.firstId = algorithm
            triple.secondId = option
            triple.value = defaultValue
            optionSupport.append(triple)
        }

        package func applyDependencies() {
            // Apply option dependencies
            for dep in optionDependencies {
                if let source = service?.getOptionData(dep.firstId),
                   let target = service?.getOptionData(dep.secondId) {
                    if let value = dep.value {
                        source.dependencies.append(Pair(first: target, second: value))
                    }
                }
            }

            // Apply option support
            for sup in optionSupport {
                if let algorithm = service?.getAlgorithmData(sup.firstId),
                   let option = service?.getOptionData(sup.secondId) {
                    algorithm.addKnownOption(option, defaultValue: sup.value)
                }
            }
        }
    }
}


// MARK: - Supporting Protocols and Classes

package protocol ILayoutMetaDataProviderRegistry {
    func register(_ algorithmData: LayoutAlgorithmData)
    func register(_ optionData: LayoutOptionData)
    func register(_ categoryData: LayoutCategoryData)
    func addDependency(_ sourceOption: String, _ targetOption: String, _ requiredValue: Any?)
    func addOptionSupport(_ algorithm: String, _ option: String, _ defaultValue: Any?)
}

extension LayoutMetaDataService.Registry: ILayoutMetaDataProviderRegistry {}
