// Phase 0 spike: can an unprivileged, same-user process suspend another
// process through Mach, or force another process's pages out?
// Every target here is a child this program forked itself.
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

extern int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);
extern int pid_suspend(int pid);
extern int pid_resume(int pid);

static uint64_t resident(pid_t pid) {
    struct rusage_info_v4 ri;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&ri) != 0) return 0;
    return ri.ri_resident_size;
}

int main(void) {
    printf("uid=%d euid=%d\n", getuid(), geteuid());

    pid_t child = fork();
    if (child == 0) { for (;;) pause(); }
    usleep(100000);

    mach_port_t task = MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), child, &task);
    printf("task_for_pid(own forked child): kr=%d (%s)\n", kr, mach_error_string(kr));
    if (kr == KERN_SUCCESS) {
        kr = task_suspend(task);
        printf("  task_suspend: kr=%d (%s)\n", kr, mach_error_string(kr));
        if (kr == KERN_SUCCESS) printf("  task_resume: kr=%d\n", task_resume(task));
    }

    mach_port_t name = MACH_PORT_NULL;
    kr = task_name_for_pid(mach_task_self(), child, &name);
    printf("task_name_for_pid: kr=%d (%s) (name ports cannot suspend or touch memory)\n", kr, mach_error_string(kr));

    int rc = pid_suspend(child);
    printf("pid_suspend (private): rc=%d errno=%d (%s)\n", rc, rc ? errno : 0, rc ? strerror(errno) : "ok");
    if (rc == 0) pid_resume(child);

    errno = 0;
    rc = memorystatus_control(1 /* GET_PRIORITY_LIST */, 0, 0, NULL, 0);
    printf("memorystatus_control(GET_PRIORITY_LIST size probe): rc=%d errno=%d (%s)\n", rc, errno, strerror(errno));
    errno = 0;
    rc = memorystatus_control(6 /* SET_JETSAM_HIGH_WATER_MARK */, child, 64, NULL, 0);
    printf("memorystatus_control(SET_JETSAM_HIGH_WATER_MARK on child): rc=%d errno=%d (%s)\n", rc, errno, strerror(errno));

    int prio_rc = setpriority(PRIO_DARWIN_PROCESS, child, PRIO_DARWIN_BG);
    printf("setpriority(PRIO_DARWIN_PROCESS, child, PRIO_DARWIN_BG): rc=%d errno=%d\n", prio_rc, prio_rc ? errno : 0);
    printf("  getpriority -> %d\n", getpriority(PRIO_DARWIN_PROCESS, child));
    setpriority(PRIO_DARWIN_PROCESS, child, 0);

    kill(child, SIGKILL);
    waitpid(child, NULL, 0);

    // Self-only reclaim paths (a process can only apply these to its own memory).
    size_t len = 256u << 20;
    char *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    for (size_t i = 0; i < len; i += 4096) p[i] = (char)(i >> 12);
    uint64_t before = resident(getpid());
    rc = madvise(p, len, MADV_PAGEOUT);
    int e = errno;
    usleep(500000);
    printf("madvise(self, 256MB, MADV_PAGEOUT): rc=%d errno=%d resident %llu -> %llu MB\n",
           rc, rc ? e : 0, before >> 20, resident(getpid()) >> 20);
    kr = mach_vm_behavior_set(mach_task_self(), (mach_vm_address_t)p, len, VM_BEHAVIOR_PAGEOUT);
    usleep(500000);
    printf("mach_vm_behavior_set(self, VM_BEHAVIOR_PAGEOUT): kr=%d (%s) resident now %llu MB\n",
           kr, mach_error_string(kr), resident(getpid()) >> 20);
    return 0;
}
