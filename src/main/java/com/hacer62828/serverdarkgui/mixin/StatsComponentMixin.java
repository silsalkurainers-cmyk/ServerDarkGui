package com.hacer62828.serverdarkgui.mixin;

import java.awt.Color;
import java.awt.Graphics;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

@Mixin(targets = "net.minecraft.server.gui.StatsComponent", remap = false)
public abstract class StatsComponentMixin {
    @Redirect(
        method = "paint",
        at = @At(
            value = "INVOKE",
            target = "Ljava/awt/Graphics;setColor(Ljava/awt/Color;)V",
            remap = false
        ),
        require = 0,
        remap = false
    )
    private void serverdarkgui$recolorStatsGraph(Graphics graphics, Color original) {
        if (original == null) {
            graphics.setColor(null);
            return;
        }

        Color replacement = original;

        boolean nearWhite = original.getRed() > 220
            && original.getGreen() > 220
            && original.getBlue() > 220;

        boolean redBar = original.getRed() > 130
            && original.getRed() > original.getGreen() * 1.25
            && original.getRed() > original.getBlue() * 1.25;

        boolean darkText = original.getRed() >= 12
            && original.getGreen() >= 12
            && original.getBlue() >= 12
            && original.getRed() < 70
            && original.getGreen() < 70
            && original.getBlue() < 70;

        if (nearWhite) {
            replacement = new Color(8, 8, 8);
        } else if (redBar || darkText) {
            replacement = new Color(70, 255, 110);
        }

        graphics.setColor(replacement);
    }
}
