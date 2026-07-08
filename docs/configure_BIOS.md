# Configuring the BIOS

This documentation describes how to configure the BIOS of an Intel NUC for compatibility with the stretch installation procedure.

## Accessing the NUC BIOS Settings

First plug in the NUC to a 19V DC power supply. Next power on the NUC using the power button on the front of the NUC.

When powered on, the NUC should display a welcome screen similar to the picture below:

![](../.gitbook/assets/NUC_startup.png)

When this label becomes visible press 'F2' to enter into the BIOS configuration menu.

!!! note

```
If you're using a Bluetooth keyboard, the BIOS likely won't recognize the F2 keypress.
```

The BIOS Settings page should look like the picture below:

![](../.gitbook/assets/BIOS_settings.png)

Select the 'Advanced' drop down menu near the top right of the screen, and then slect the option 'Boot'

![](../.gitbook/assets/BIOS_advanced.png)

From the 'Boot' settings page select the 'Secure Boot' tab.

![](../.gitbook/assets/BIOS_secure_boot_tab.png)

Turn off 'Secure Boot' by toggling the checkbox labeled 'Secure Boot' to unchecked.

![](../.gitbook/assets/BIOS_secure_boot_check.png)

Next Select the 'Power' tab

![](../.gitbook/assets/BIOS_power_tab.png)

From the power settings screen select the 'Power On' option from the 'After Power Failure' drop down selection.

![](../.gitbook/assets/BIOS_power_settings.png)

Next Select the Security tab

![](../.gitbook/assets/BIOS_security_tab.png)

Turn on UEFI third party drivers compatibility by toggling the checkbox labeled 'Allow UEFI Third Party Driver loaded' to checked.

![](../.gitbook/assets/BIOS_security_settings.png)

Now use the F10 key to save BIOS configuration changes and exit.

***

All materials are Copyright 2020-2026 by Hello Robot Inc. Hello Robot and Stretch are registered trademarks.
