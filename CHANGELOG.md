# Changelog

## [1.3.1](https://github.com/joshuafuller/atak-vns-offline-routing-generator/compare/v1.3.0...v1.3.1) (2025-08-27)


### Bug Fixes

* separate Release Please from Docker builds for proper semver tagging ([2572319](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/2572319))

## [1.3.0](https://github.com/joshuafuller/atak-vns-offline-routing-generator/compare/v1.2.0...v1.3.0) (2025-08-27)


### Features

* add Windows Git Bash compatibility to list-regions.sh ([3a0a7a1](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/3a0a7a1)), closes [#5](https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues/5)
* fix OutOfMemoryError with intelligent memory management system ([29a3cb4](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/29a3cb4)), closes [#8](https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues/8)
* implement Release Please for automated semantic versioning ([72e4a37](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/72e4a37))


### Bug Fixes

* correct region examples in README to match list-regions output ([ee88ac4](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/ee88ac4))
* improve GitHub Actions naming and permissions ([befadfe](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/befadfe))
* update to non-deprecated release-please action ([96d821a](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/96d821a))


### Documentation

* update architecture documentation for GraphHopper v1.0 integration ([0c141a5](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/0c141a5))

## [1.2.0](https://github.com/joshuafuller/atak-vns-offline-routing-generator/compare/v1.1.0...v1.2.0) (2025-08-25)


### Features

* optimize Docker build with pre-built GraphHopper JARs ([eebf42a](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/eebf42a))


### Performance Improvements

* optimize Docker build with multi-stage approach for faster CI/CD ([459e4c3](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/459e4c3))


### Documentation

* add instant try section to README ([a6ef062](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/a6ef062))

## [1.1.0](https://github.com/joshuafuller/atak-vns-offline-routing-generator/compare/v1.0.0...v1.1.0) (2025-08-25)


### Features

* implement automatic semantic versioning with CI/CD ([b0ee817](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/b0ee817))


### Bug Fixes

* correct YAML syntax in GitHub Actions workflow ([77dbaec](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/77dbaec))
* simplify CI/CD pipeline using docker metadata-action only ([bd757b1](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/bd757b1))


### Documentation

* update documentation for v1.1 with worldwide region support ([58d286f](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/58d286f))

## [1.0.0](https://github.com/joshuafuller/atak-vns-offline-routing-generator/releases/tag/v1.0.0) (2025-08-24)


### Features

* initial release: ATAK VNS Offline Routing Generator ([e932149](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/e932149))
* eliminate Python dependency and add worldwide region support ([36b73ea](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/36b73ea)), closes [#1](https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues/1)
* add CI/CD pipeline with GitHub Container Registry ([5994f88](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/5994f88))


### Documentation

* update README with actual tested output sizes ([5c14fae](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/5c14fae))


### Miscellaneous

* bump Docker image version to 1.1 ([45285c5](https://github.com/joshuafuller/atak-vns-offline-routing-generator/commit/45285c5))