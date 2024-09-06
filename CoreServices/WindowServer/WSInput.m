/*
 * Copyright (C) 2022-2024 Zoe Knox <zoe@pixin.net>
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "common.h"
#import "WSInput.h"

static unichar translateKeySym(xkb_keysym_t keysym) {
     switch(keysym) {
        case XKB_KEY_Home:
        case XKB_KEY_KP_Home: return NSHomeFunctionKey;
        case XKB_KEY_Left:
        case XKB_KEY_KP_Left: return NSLeftArrowFunctionKey;
        case XKB_KEY_Up:
        case XKB_KEY_KP_Up: return NSUpArrowFunctionKey;
        case XKB_KEY_Right:
        case XKB_KEY_KP_Right: return NSRightArrowFunctionKey;
        case XKB_KEY_Down:
        case XKB_KEY_KP_Down: return NSDownArrowFunctionKey;
        case XKB_KEY_Page_Up:
        case XKB_KEY_KP_Page_Up: return NSPageUpFunctionKey;
        case XKB_KEY_Page_Down:
        case XKB_KEY_KP_Page_Down: return NSPageDownFunctionKey;
        case XKB_KEY_End:
        case XKB_KEY_KP_End: return NSEndFunctionKey;
        case XKB_KEY_Begin:
        case XKB_KEY_KP_Begin: return NSHomeFunctionKey;
        case XKB_KEY_Delete:
        case XKB_KEY_KP_Delete: return NSDeleteFunctionKey;
        case XKB_KEY_Insert:
        case XKB_KEY_KP_Insert: return NSInsertFunctionKey;
        case XKB_KEY_F1: return NSF1FunctionKey;
        case XKB_KEY_F2: return NSF2FunctionKey;
        case XKB_KEY_F3: return NSF3FunctionKey;
        case XKB_KEY_F4: return NSF4FunctionKey;
        case XKB_KEY_F5: return NSF5FunctionKey;
        case XKB_KEY_F6: return NSF6FunctionKey;
        case XKB_KEY_F7: return NSF7FunctionKey;
        case XKB_KEY_F8: return NSF8FunctionKey;
        case XKB_KEY_F9: return NSF9FunctionKey;
        case XKB_KEY_F10: return NSF10FunctionKey;
        case XKB_KEY_F11: return NSF11FunctionKey;
        case XKB_KEY_F12: return NSF12FunctionKey;
        case XKB_KEY_F13: return NSF13FunctionKey;
        case XKB_KEY_F14: return NSF14FunctionKey;
        case XKB_KEY_F15: return NSF15FunctionKey;
        case XKB_KEY_F16: return NSF16FunctionKey;
        case XKB_KEY_F17: return NSF17FunctionKey;
        case XKB_KEY_F18: return NSF18FunctionKey;
        case XKB_KEY_F19: return NSF19FunctionKey;
        case XKB_KEY_F20: return NSF20FunctionKey;
        case XKB_KEY_F21: return NSF21FunctionKey;
        case XKB_KEY_F22: return NSF22FunctionKey;
        case XKB_KEY_F23: return NSF23FunctionKey;
        case XKB_KEY_F24: return NSF24FunctionKey;
        case XKB_KEY_F25: return NSF25FunctionKey;
        case XKB_KEY_F26: return NSF26FunctionKey;
        case XKB_KEY_F27: return NSF27FunctionKey;
        case XKB_KEY_F28: return NSF28FunctionKey;
        case XKB_KEY_F29: return NSF29FunctionKey;
        case XKB_KEY_F30: return NSF30FunctionKey;
        case XKB_KEY_F31: return NSF31FunctionKey;
        case XKB_KEY_F32: return NSF32FunctionKey;
        case XKB_KEY_F33: return NSF33FunctionKey;
        case XKB_KEY_F34: return NSF34FunctionKey;
        case XKB_KEY_F35: return NSF35FunctionKey;
        default: return keysym;
    }
}

@implementation WSInput

-init {
    udev = udev_new();
    li = libinput_udev_create_context(&interface, NULL, udev);
    libinput_udev_assign_seat(li, "seat0");

    xkbCtx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    xkb_state = xkb_state_unmodified = NULL;
    xkb_keymap = NULL;
    [self setKeymap];

    return self;
}

-(void)dealloc {
    xkb_keymap_unref(xkb_keymap);
    xkb_state_unref(xkb_state);
    xkb_state_unref(xkb_state_unmodified);
    xkb_context_unref(xkbCtx);
    libinput_unref(li);
    udev_unref(udev);
}

-(void)run:(id)target {
    struct libinput_event *event = NULL;

    libinput_dispatch(li);
    while((event = libinput_get_event(li)) != NULL) {
        [self processEvent:event target:target];
        libinput_event_destroy(event);
        libinput_dispatch(li);
    }
}

-(void)setLogLevel:(int)level {
    logLevel = level;
}

/* event is destroyed after this function returns */
-(void)processEvent:(struct libinput_event *)event target:(NSObject *)target {
    enum libinput_event_type etype = libinput_event_get_type(event);
    if(logLevel >= WS_INFO)
        NSLog(@"input event: device %s type %d",
        libinput_device_get_name(libinput_event_get_device(event)), etype);
    
    switch(etype) {
        case LIBINPUT_EVENT_KEYBOARD_KEY: {
            struct libinput_event_keyboard *ke = libinput_event_get_keyboard_event(event);
            uint32_t keycode = libinput_event_keyboard_get_key(ke);
            enum libinput_key_state state = libinput_event_keyboard_get_key_state(ke);
            if(logLevel >= WS_INFO)
                NSLog(@"Input event: type=KEY key=%u state=%u", keycode, state);

            keycode += 8; // evdev keycode offset
            xkb_keysym_t sym = xkb_state_key_get_one_sym(xkb_state, keycode);
            if(sym == XKB_KEY_NoSymbol)
                return;
            xkb_state_update_key(xkb_state, keycode, state == LIBINPUT_KEY_STATE_PRESSED
                    ? XKB_KEY_DOWN : XKB_KEY_UP);

            unichar nskey = translateKeySym(sym);
            NSString *strChars, *strCharsIg;

            if(nskey == sym) { // we did not translate, look up the utf8
                char buf[128];
                xkb_state_key_get_utf8(xkb_state, keycode, buf, sizeof(buf));
                strChars = [NSString stringWithUTF8String:buf];
                xkb_state_key_get_utf8(xkb_state_unmodified, keycode, buf, sizeof(buf));
                strCharsIg = [NSString stringWithUTF8String:buf];
            } else {
                strChars = [NSString stringWithCharacters:&nskey length:1];
                strCharsIg = strChars;
            }

            // FIXME: handle autorepeat
            NSEvent *ev = [NSEvent keyEventWithType:state == LIBINPUT_KEY_STATE_PRESSED
                                                    ? NSKeyDown : NSKeyUp
                                      location:NSZeroPoint // FIXME: use pointer pos
                                 modifierFlags:[self modifierFlagsForState:xkb_state]
                                     timestamp:0.0
                                  windowNumber:0 // FIXME: use active window number
                                       context:nil
                                    characters:strChars
                   charactersIgnoringModifiers:strCharsIg
                                     isARepeat:NO
                                       keyCode:keycode];
            [target sendEventToApp:ev];
        }
        default:
            if(logLevel >= WS_WARNING)
                NSLog(@"Unhandled input event type %u", etype);
            return;
    }
}

// this reads the default system keymap. Call it after changing the default from prefs.
-(void)setKeymap {
    xkb_keymap_unref(xkb_keymap);
    xkb_keymap = xkb_keymap_new_from_names(xkbCtx, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if(xkb_state)
        xkb_state_unref(xkb_state);
    if(xkb_state_unmodified)
        xkb_state_unref(xkb_state_unmodified);
    xkb_state = xkb_state_new(xkb_keymap);
    xkb_state_unmodified = xkb_state_new(xkb_keymap);
}

-(unsigned int)modifierFlagsForState:(struct xkb_state *)state {
    unsigned int ret=0;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSShiftKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_CTRL, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSControlKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_LOGO, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSCommandKeyMask;
    if(xkb_state_mod_name_is_active(state, XKB_MOD_NAME_ALT, XKB_STATE_MODS_EFFECTIVE))
        ret |= NSAlternateKeyMask;
    return ret;
}


@end
