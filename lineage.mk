#
# Copyright (C) 2017 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from gohan device
$(call inherit-product, device/bq/gohan/device.mk)

# Set those variables here to overwrite the inherited values.
BOARD_VENDOR := bq
PRODUCT_BRAND := bq
PRODUCT_DEVICE := gohan
PRODUCT_NAME := lineage_gohan
PRODUCT_MANUFACTURER := bq
PRODUCT_MODEL := Aquaris X5 Plus
TARGET_VENDOR := bq

# Set product device & name
PRODUCT_BUILD_PROP_OVERRIDES += \
   TARGET_DEVICE=Aquaris_X5_Plus PRODUCT_NAME=Aquaris_X5_Plus

PRODUCT_GMS_CLIENTID_BASE := android-bq

# Vendor security patch level
PRODUCT_PROPERTY_OVERRIDES += \
    ro.lineage.build.vendor_security_patch=2018-09-01

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="gohan-user 7.1.1 NMF26F 2.6.0_20180628-1433 release-keys"

BUILD_FINGERPRINT := bq/Aquaris_X5_Plus/Aquaris_X5_Plus:7.1.1/NMF26F/676:user/release-keys
