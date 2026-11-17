package com.hacer62828.serverdarkgui.mixin;

import java.awt.Color;
import javax.swing.UIManager;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(targets = "net.minecraft.server.gui.MinecraftServerGui", remap = false)
public abstract class MinecraftServerGuiMixin {
    @Inject(method = "<init>", at = @At(value = "HEAD", remap = false), remap = false)
    private void serverdarkgui$applyDarkTheme(CallbackInfo ci) {
        try {
            UIManager.setLookAndFeel(UIManager.getCrossPlatformLookAndFeelClassName());
        } catch (Exception ignored) {
            // Keep the current look and feel if the platform rejects the change.
        }

        Color background = new Color(12, 12, 12);
        Color panel = new Color(18, 18, 18);
        Color green = new Color(70, 255, 110);
        Color selection = new Color(25, 90, 45);

        UIManager.put("Panel.background", panel);
        UIManager.put("Panel.foreground", green);
        UIManager.put("Viewport.background", background);
        UIManager.put("ScrollPane.background", background);
        UIManager.put("TextArea.background", background);
        UIManager.put("TextArea.foreground", green);
        UIManager.put("TextArea.caretForeground", green);
        UIManager.put("TextArea.selectionBackground", selection);
        UIManager.put("TextArea.selectionForeground", Color.WHITE);
        UIManager.put("TextField.background", background);
        UIManager.put("TextField.foreground", green);
        UIManager.put("TextField.caretForeground", green);
        UIManager.put("TextField.selectionBackground", selection);
        UIManager.put("TextField.selectionForeground", Color.WHITE);
        UIManager.put("Label.foreground", green);
        UIManager.put("List.background", background);
        UIManager.put("List.foreground", green);
        UIManager.put("List.selectionBackground", selection);
        UIManager.put("List.selectionForeground", Color.WHITE);
        UIManager.put("TabbedPane.background", panel);
        UIManager.put("TabbedPane.foreground", green);
        UIManager.put("TabbedPane.selected", background);
        UIManager.put("TitledBorder.titleColor", green);
        UIManager.put("Separator.background", new Color(45, 65, 45));
        UIManager.put("Button.background", panel);
        UIManager.put("Button.foreground", green);
        UIManager.put("control", panel);
        UIManager.put("info", panel);
        UIManager.put("text", green);
        UIManager.put("nimbusBase", background);
        UIManager.put("nimbusBlueGrey", panel);
        UIManager.put("nimbusLightBackground", background);
    }
}
