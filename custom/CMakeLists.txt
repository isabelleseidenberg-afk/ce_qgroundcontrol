message(STATUS "QGC: Adding Crown & Eagle Engineering Custom Plugin")
# ============================================================================
# Custom Resources
# ============================================================================
set(CUSTOM_RESOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/custom.qrc
    CACHE INTERNAL "" FORCE
)
set(QGC_RESOURCES ${QGC_RESOURCES} ${CUSTOM_RESOURCES})
list(REMOVE_DUPLICATES QGC_RESOURCES)
set(QGC_RESOURCES ${QGC_RESOURCES} PARENT_SCOPE)
# ============================================================================
# Custom Plugin Sources
# ============================================================================
set(CUSTOM_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/CustomPlugin.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/CustomPlugin.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/QGCRosBridgeClient.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/QGCRosBridgeClient.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/AutoPilotPlugin/CustomAutoPilotPlugin.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/AutoPilotPlugin/CustomAutoPilotPlugin.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/FirmwarePlugin/CustomFirmwarePlugin.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/FirmwarePlugin/CustomFirmwarePlugin.h
    ${CMAKE_CURRENT_SOURCE_DIR}/src/FirmwarePlugin/CustomFirmwarePluginFactory.cc
    ${CMAKE_CURRENT_SOURCE_DIR}/src/FirmwarePlugin/CustomFirmwarePluginFactory.h
    CACHE INTERNAL "" FORCE
)
# ============================================================================
# Custom Build Configuration
# ============================================================================
set(CUSTOM_LIBRARIES
    CACHE INTERNAL "" FORCE
)
set(CUSTOM_INCLUDE_DIRECTORIES
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/AutoPilotPlugin
    ${CMAKE_CURRENT_SOURCE_DIR}/src/FirmwarePlugin
    CACHE INTERNAL "" FORCE
)
set(CUSTOM_DEFINITIONS
    QGC_CUSTOM_BUILD
    CUSTOMHEADER="CustomPlugin.h"
    CUSTOMCLASS=CustomPlugin
    CACHE INTERNAL "" FORCE
)
set(CUSTOM_QT_COMPONENTS
    Core
    Network
    CACHE INTERNAL "" FORCE
)
