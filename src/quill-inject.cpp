// quill-inject: a tiny, dependency-free virtual keyboard key injector.
//
// Reads key actions from stdin, one per line, in the form:
//     d <linux-keycode>   (key press / down)
//     u <linux-keycode>   (key release / up)
// and injects them into the system through the Linux uinput kernel
// interface. No network, no external libraries, no root required
// (just read/write access to /dev/uinput).
//
// SPDX-License-Identifier: MIT

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/input.h>
#include <linux/uinput.h>

static int g_fd = -1;

static bool open_uinput() {
  g_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK);
  if (g_fd < 0) {
    g_fd = open("/dev/input/uinput", O_WRONLY | O_NONBLOCK);
  }
  if (g_fd < 0) {
    std::fprintf(stderr,
      "quill-inject: cannot open /dev/uinput\n"
      "  grant access: add your user to the 'input' group, or install the\n"
      "  provided udev rule (udev/99-quill-uinput.rules) and reload udev.\n");
    return false;
  }

  if (ioctl(g_fd, UI_SET_EVBIT, EV_KEY) < 0) {
    std::perror("quill-inject: UI_SET_EVBIT EV_KEY");
    return false;
  }
  if (ioctl(g_fd, UI_SET_EVBIT, EV_SYN) < 0) {
    std::perror("quill-inject: UI_SET_EVBIT EV_SYN");
    return false;
  }
  // Advertise support for the full key range so any code we send is accepted.
  for (int c = 0; c < KEY_MAX; c++) {
    ioctl(g_fd, UI_SET_KEYBIT, c);
  }

  struct uinput_setup setup;
  std::memset(&setup, 0, sizeof(setup));
  setup.id.bustype = BUS_USB;
  setup.id.vendor = 0x1234;
  setup.id.product = 0x5678;
  std::strncpy(setup.name, "Quill Virtual Keyboard",
               UINPUT_MAX_NAME_SIZE - 1);
  setup.name[UINPUT_MAX_NAME_SIZE - 1] = '\0';

  if (ioctl(g_fd, UI_DEV_SETUP, &setup) < 0) {
    std::perror("quill-inject: UI_DEV_SETUP");
    return false;
  }
  if (ioctl(g_fd, UI_DEV_CREATE) < 0) {
    std::perror("quill-inject: UI_DEV_CREATE");
    return false;
  }
  return true;
}

static void send_event(__u16 type, __u16 code, __s32 value) {
  struct input_event ev;
  std::memset(&ev, 0, sizeof(ev));
  ev.type = type;
  ev.code = code;
  ev.value = value;
  if (write(g_fd, &ev, sizeof(ev)) < 0) {
    std::perror("quill-inject: write");
  }
}

static void key_event(int code, int down) {
  // Defence: only forward codes inside the valid range.
  if (code < 0 || code >= KEY_MAX) return;
  send_event(EV_KEY, static_cast<__u16>(code), down ? 1 : 0);
  send_event(EV_SYN, SYN_REPORT, 0);
}

int main() {
  if (!open_uinput()) return 1;

  char buf[64];
  while (std::fgets(buf, sizeof(buf), stdin)) {
    char action = buf[0];
    int code = std::atoi(buf + 1);
    if (action == 'd' || action == 'D') {
      key_event(code, 1);
    } else if (action == 'u' || action == 'U') {
      key_event(code, 0);
    }
  }

  if (g_fd >= 0) {
    ioctl(g_fd, UI_DEV_DESTROY);
    close(g_fd);
  }
  return 0;
}
