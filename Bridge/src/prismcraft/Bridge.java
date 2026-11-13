package prismcraft;

import java.nio.file.*;
import java.util.*;
import com.mojang.blaze3d.platform.InputConstants;
import net.minecraft.client.*;
import net.minecraft.client.input.MouseButtonInfo;
import net.minecraft.client.gui.screens.inventory.InventoryScreen;
import net.minecraft.client.gui.screens.PauseScreen;
import net.minecraft.client.gui.screens.inventory.CreativeModeInventoryScreen;
import org.lwjgl.sdl.SDLMouse;
import net.minecraft.network.chat.Component;

public final class Bridge {
    private static final Path FILE = Path.of(System.getProperty("user.home"), "Library", "Application Support", "Prism Craft", "controls");
    private static final Set<KeyMapping> held = new HashSet<>();
    private static long lastAck, lastAimFrame;
    private static boolean armed, toggleWasDown;
    private static String session = "";
    private static long jump, place, inventory, pause, drop, view;
    private static boolean menuOwned;
    private static int lastSlot;
    private static boolean inventoryPending, inventoryOwned, cursorDown, cursorReady;
    private static final MouseButtonInfo RIGHT = new MouseButtonInfo(InputConstants.MOUSE_BUTTON_RIGHT,0);
    private static final MouseButtonInfo LEFT = new MouseButtonInfo(InputConstants.MOUSE_BUTTON_LEFT,0);
    private static double clamp(double x) { return Double.isFinite(x) ? Math.max(-1, Math.min(1,x)) : 0; }
    private static void hold(KeyMapping key, boolean down) {
        if (down) {
            boolean started = held.add(key);
            if (!key.isDown()) key.setDown(true);
            if (started && key.isDown()) KeyMapping.click(InputConstants.getKey(key.saveString()));
        } else if (held.remove(key)) key.setDown(false);
    }
    private static void release() {
        for (KeyMapping key: held) key.setDown(false);
        held.clear();
    }
    private static void ack(String status) {
        long now = System.currentTimeMillis();
        if (now-lastAck < 350) return;
        lastAck=now;
        try {
            Files.createDirectories(FILE.getParent());
            Path next=FILE.resolveSibling("status.next");
            Files.writeString(next,now+" "+status);
            Files.move(next,FILE.resolveSibling("status"),StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception ignored) {}
    }
    private static void releaseCursor(Minecraft client) {
        if (cursorDown) client.mouseHandler.onButton(client.getWindow().handle(),LEFT,InputConstants.RELEASE);
        cursorDown=false;cursorReady=false;
    }
    public static void tick(Minecraft client) {
        boolean allowed = client.player != null && client.level != null && client.hasSingleplayerServer() && client.isWindowActive();
        var screen=client.gui.screen();
        boolean inventoryScreen=screen instanceof InventoryScreen || screen instanceof CreativeModeInventoryScreen;
        boolean pauseScreen=screen instanceof PauseScreen;
        if (!pauseScreen) menuOwned=false;
        boolean world=allowed && screen==null && !client.isPaused();
        if (allowed && inventoryScreen && inventoryPending) { inventoryOwned=true;inventoryPending=false;cursorReady=false; }
        if (!inventoryScreen) { inventoryOwned=false;releaseCursor(client); }
        boolean inventoryActive=allowed && inventoryScreen && inventoryOwned;
        boolean toggle=InputConstants.isKeyDown(InputConstants.KEY_F8);
        boolean menuActive=allowed && pauseScreen && menuOwned;
        if (!world && !inventoryActive && !menuActive) {
            ack(client.level != null && client.hasSingleplayerServer() ? "paused":"loaded");armed=false;inventoryOwned=false;inventoryPending=false;
            release();releaseCursor(client);toggleWasDown=toggle;return;
        }
        if (toggle && !toggleWasDown) {
            armed=!armed;session="";
            client.player.sendOverlayMessage(Component.literal(armed ? "Prism Craft armed · F8 to stop" : "Prism Craft off"));
        }
        toggleWasDown=toggle;
        if (!armed) { ack("ready");release();releaseCursor(client);return; }
        try {
            if (Files.size(FILE)>512) throw new IllegalArgumentException();
            String[] f=Files.readString(FILE).strip().split(" ");
            if (f.length!=20 || !f[0].equals("4")) throw new IllegalArgumentException();
            long stamp=Long.parseLong(f[1]);
            long age=System.currentTimeMillis()-stamp;
            if (age< -40 || age>250) throw new IllegalArgumentException();
            double x=clamp(Double.parseDouble(f[3])),y=clamp(Double.parseDouble(f[4]));
            double yaw=clamp(Double.parseDouble(f[5])),pitch=clamp(Double.parseDouble(f[6]));
            long j=Long.parseLong(f[8]),p=Long.parseLong(f[9]),inv=Long.parseLong(f[10]);
            int slot=Integer.parseInt(f[11]);
            long pa=Long.parseLong(f[16]),dr=Long.parseLong(f[17]),vi=Long.parseLong(f[18]);
            if (!session.equals(f[2])) { session=f[2];jump=j;place=p;inventory=inv;pause=pa;drop=dr;view=vi;lastSlot=slot;lastAimFrame=stamp;releaseCursor(client); }
            boolean pauseEdge=pa>pause, inventoryEdge=inv>inventory;
            pause=pa;inventory=inv;
            if (pauseEdge || (inventoryActive && inventoryEdge)) {
                release();releaseCursor(client);jump=j;place=p;drop=dr;view=vi;
                if (inventoryActive || menuActive) { client.gui.setScreen(null);inventoryOwned=false;menuOwned=false; }
                else { client.gui.setScreen(new PauseScreen(true));menuOwned=true; }
                return;
            }
            if (inventoryActive || menuActive) {
                ack(inventoryActive ? "inventory":"menu");release();drop=dr;view=vi;
                double cx=Double.parseDouble(f[12]),cy=Double.parseDouble(f[13]);
                if (!(cx>=0 && cx<=1 && cy>=0 && cy<=1)) { releaseCursor(client);return; }
                var w=client.getWindow();
                float px=(float)(cx*Math.max(1,w.getScreenWidth()-1)),py=(float)(cy*Math.max(1,w.getScreenHeight()-1));
                SDLMouse.SDL_WarpMouseInWindow(w.handle(),px,py);
                client.mouseHandler.onMove(w.handle(),px,py,0,0);
                hold(client.options.keyShift,f[19].equals("1"));
                if (p>place) {
                    client.mouseHandler.onButton(w.handle(),RIGHT,InputConstants.PRESS);
                    client.mouseHandler.onButton(w.handle(),RIGHT,InputConstants.RELEASE);
                }
                boolean down=f[14].equals("1");
                if (!down) cursorReady=true;
                boolean desired=down && cursorReady;
                if (desired!=cursorDown) {
                    client.mouseHandler.onButton(w.handle(),LEFT,desired ? InputConstants.PRESS:InputConstants.RELEASE);
                    cursorDown=desired;
                }
                jump=j;place=p;inventory=inv;lastSlot=slot;
                return;
            }
            ack("receiving");
            var o=client.options;
            if (inventoryEdge) {
                release();KeyMapping.click(InputConstants.getKey(o.keyInventory.saveString()));
                inventoryPending=true;inventory=inv;jump=j;place=p;lastSlot=slot;return;
            }
            inventory=inv;
            hold(o.keyLeft,x< -0.13);hold(o.keyRight,x>0.13);
            hold(o.keyUp,y>0.13);hold(o.keyDown,y< -0.13);hold(o.keySprint,y>0.13 && f[15].equals("1"));
            hold(o.keyShift,f[19].equals("1"));
            if (dr>drop) KeyMapping.click(InputConstants.getKey(o.keyDrop.saveString()));
            if (vi>view) KeyMapping.click(InputConstants.getKey(o.keyTogglePerspective.saveString()));
            drop=dr;view=vi;
            hold(o.keyAttack,f[7].equals("1"));hold(o.keyJump,j>jump);
            if (p>place) KeyMapping.click(InputConstants.getKey(o.keyUse.saveString()));
            if (slot!=lastSlot && slot>=1 && slot<=9) client.player.getInventory().setSelectedSlot(slot-1);
            lastSlot=slot;jump=j;place=p;
            if (stamp>lastAimFrame) {
                lastAimFrame=stamp;
                if (age<=135 && (yaw!=0 || pitch!=0)) client.player.turn(yaw*17,pitch*12);
            }
        } catch (Exception ignored) { ack(inventoryActive ? "inventory":"armed");release();releaseCursor(client); }
    }
}
