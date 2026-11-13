package prismcraft.mixin;
import prismcraft.Bridge;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
@Mixin(Minecraft.class)
public class GameTick {
    @Inject(method="tick",at=@At("HEAD"))
    private void prismCraftTick(CallbackInfo ci) { Bridge.tick((Minecraft)(Object)this); }
}
