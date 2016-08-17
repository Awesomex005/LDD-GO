
http://www.makelinux.net/ldd3/   2月20号开始学习      
**未细学习章节  或  还有疑问的章节**
第四章 调试技术 
第五章 并发和竞态-除了锁之外的办法
第六章 高级字符驱动程序操作 异步通知 poll和select
第六章 设备文件的访问控制 在打开时复制设备（TTY类似的的实现原理） 有意思可以再次阅读

关于io_remap与IO_ADDRESS 映射I/O memory http://blog.csdn.net/liuxd3000/article/details/16819921
asm/irq.h 中的NR_IRQS
BMC分配中断号的依据
中断处理的内幕 arch/i386/kernel/irq.c, arch/i386/kernel/apic.c, arch/i386/kernel/entry.S, arch/i386/kernel/i8259.c, and include/asm-i386/hw_irq.h as they appear in the 2.6 kernels; although the general concepts remain the same, the hardware details differ on other platforms.

https://github.com/martinezjavier/ldd3

---
# 自旋锁 信号量 互斥量 使用原则
**自旋锁**在锁被占用时，忙循环不断检测锁的状态。内核中的互斥多数用自旋锁机制实现。和信号量不同，**自旋锁可在不能休眠的代码中使用，比如中断处理函数**。自旋锁可以提供比信号量更高的性能。

1.  在必须获得多个锁时，应该始终按相同的顺序获得锁。
2.  在必须获得一个局部锁，和一个内核更中心位置的锁时，先获取自己的局部锁。
3.  在需要获取信号量和自旋锁时，首先索取信号量。
4.  在拥有自旋锁后调用```down```或者```copy_from/to_user```或者```kmalloc(..,GFP_KERNEL)```(可导致休眠) 是个极其严重的错误（**获得自旋锁后不应因任何理由放弃处理器，中断是个例外（某些情况下此时也不能放弃处理器）**）。
5. 内核抢占的情况由自旋锁代码本身处理。任何时候，只要内核代码拥有自旋锁，在相关处理器上的抢占就会被禁止。
6.  驱动程序（非中断例程），和中断服务例程需要同一个锁时，驱动程序应使用```spin_lock_irqsave() /spin_unlock_irqrestore()```, 中断服务例程使用```spin_lock() /spin_unlock()``` (中断服务例程应已自行关闭本设备的所有中断)。否则驱动程序获得锁后，中断来临，中断服务例程在该锁上自旋，若两段代码在同一处理器上运行则造成死锁。
7. 软件中断会访问，硬件中断不会访问的自旋锁应使用```spin_lock_bh() /spin_unlock_bh()```，以便安全使用锁的同时，硬件中断能正常工作。
8. 自旋锁保护的内容应该尽可能短小，避免长时间占有锁。

lockmeter可以度量内核花费在锁上的时间。

---
# 处于进程上下文之外（如在软硬中断上下文之中）（原子上下文中）需要遵守的规则：
- 不允许访问用户空间。它不在任何进程上下文中执行，无法把任何特定进程和用户空间关联起来。
- current指针在原子模式下没有任何意义，且不可用，因为相关的代码和被中断的进程没有任何关联。
- 不能执行休眠或者调度。原子代码不可调用```schedule```，```wait_event```，也不能任何可以引起休眠的函数，如```kmalloc(..,GFP_KERNEL)```，信号量，```copy_to_user()```。   (kmalloc(..,GFP_ATOMIC)在原子上下文中是可用的)
- 需要访问有可能产生竞争的数据应使用自旋锁。

---
系统调用返回-ERESTARTSYS时，内核的高层代码要么会重新调用该调用，要么会将错误返回给用户。如果我们返回-ERESTARTSYS，则必须首先撤销已经做出的任何用户可见的修改。这样，系统调用可正确重新被调用。如果无法撤销这些操作，则应返回-EINTR。
    if (down_interruptible(&dev->sem)) /* 被中断则返回-ERESTARTSYS */
        return -ERESTARTSYS;
LDD3第五章

---
semaphore
用户空间  <semaphore.h>    sem_init(sem_t *sem, int pshared, unsigned int value);
内核空间   <linux/semaphore.h>    sema_init(struct semaphore *sem, int val);

---
软件中断是打开硬件中断的同时中行某些异步任务的一种内核机制。

---
if( printk_ratelimit() )
        printk(KERN_ALERT "something.\n");

---
限制打印次数,频率。
内核无法直接访问用户空间内存的原因：
1. 在内核里用户空间的指针可能是无效的，
2.即使该指针在内核空间中代表相同的东西，但是用户空间的内存是分页的，在系统调用被调用时，涉及的内存可能根本不在RAM中。直接访问会导致页错误。
3.安全性问题。比如用户程序可能存在缺陷或恶意代码。

---

# 文件描述符（一些非负整数），文件描述符表 与 file结构体 
每个进程在PCB（Process Control Block）中都保存着一份**文件描述符表** ```struct files_struct *files; /* open file information */```，**文件描述符**就是这个表的索引， 文件描述表中每个表项都有一个指向已打开文件的指针，现在我们明确一下：已打开的文件在内核中用**file结构体**表示```struct file{ } <include/linux/fs.h>```，文件描述符表中的指针指向file结构体。

进程1和进程2分别打开同一文件，它们会各自拥有不同的file结构体指向该文件，因此可以有不同的File Status Flag(f_flags<打开文件的权限>)和读写位置(f_pos)。(同一个文件被open两次产生量个不同的file结构体)

file结构体中比较重要的成员还有```f_count```，表示引用计数（Reference Count）， ```dup```、```fork```等系统调用会导致多个文件描述符指向同一个file结构体，例如有```fd1```和```fd2```都引用同一个file结构体，那么它的引用计数就是2，当```close(fd1)```时并不会释放file结构体，而只是把引用计数减到1，如果再```close(fd2)```，引用计数就会减到0同时调用驱动中的```release```函数（实测）并释放file结构体，这才真的关闭了文件。也就是说**新的file结构体仅有```open```产生**，```fork/dup```只会让已有的file结构体的```f_count```增加而不创建新的file结构体。

FILE结构体定义在c库中，不会在内核中出现。

---
LDD3 中文 64页， 
在应用程序还未显示地关闭它所打开的文件就终止时，内核会通过在内部使用close系统调用自动关闭所有相关的文件。

---
# 设备号 设备节点
- 在用户空间可以访问设备号之前，驱动程序需要将设备号和内部函数连接起来，这些内部函数用来实现设备的操作。
- 动态分配设备号的缺点是不能提前创建设备节点，我们可以在装载模块时是使用脚本来完成。相对的在卸载模块时也用脚本完成。另外我们还可以把这些脚本做成init脚本（位于```/etc/init.d```目录下的脚本）。 

对应于主设备号1（/dev/null , /dev/zero等等）的open代码根据要打开的次设备号替换filp->f_op中的操作。这种技巧允许相同主设备号下的设备实现多种操作行为，而不会增加系统调用的负担。这种替换文件的操作的能力在面向对象的编程技术里成为“方法重载”。

---
# 三个重要的数据结构 file_operations file inode
- file结构体包含成员file_operations，``` struct file_operations *f_op```。内核执行open操作时对```filp->f_op```赋值，以后需要执行文件操作时就读取这个指针。```filp->f_op```的值不会被保存起来，在需要的时候会被修改。
- file结构体包含成员```void* private_data;```，open系统调用在调用驱动程序的open前把这个指针赋值为NULL。驱动程序可以把这个指针用于任何目的，也可以忽略它，在需要跨系统调用保存共用数据时```private_data```是非常好用的。
- 内核用inode结构在内部表示文件，因此它和file不同，后者表示打开的文件描述符。对于单个文件，可能会有许多个表示打开的文件描述符的file，但它们都指向一个inode。
- inode有两个与驱动编程相关较大的字段。
    - ```dev_t i_rdev;```当inode指向一个设备文件时，这个字段表示该设备的设备号。
    - ```struct cdev *i_cdev;``` ```struct cdev```是内核内部表示字符设备的结构。当inode指向一个字符设备文件时，该字段包含了指向```struct cdev```的指针。
        - 内核在调用字符设备之前，必须分配并注册一个或者多个struct cdev。为此相应的代码需要```#include <linux/cdev.h>```。
            - 注册cdev后，设备就生效了，应把必要的初始化做完后在注册cdev，如信号量，互斥量。
        - cdev中也包含struct file_operations成员。

---
# 内核中不能直接使用用户空间的指针
- 该地址可能根本无法映射到内核空间，或者可能指向某些随机数据。
- 即使该指针在内核空间中代表相同的东西，但用户空间的内存是分也的，在系统调用时被调用时，涉及的内存可能更本不在RAM中（用户空间内存可交换，内核空间内存不可交换）。对用户空间内存的直接引用将导致页错误，并进而导致调用该系统调用的进程死亡。
- 调用系统调用的程序可能是有缺陷的或者是个恶意程序，驱动程序盲目的使用用户提供的指针将导致系统出现打开的后门。

---
Before a user-space program can access one of those device numbers, your driver needs to connect them to its internal functions that implement the device's operations.

---
**kmalloc**能够分配的内存块大小存在一个上限。这个上限随体系结构不同和内核配置选项不同而变化。如果希望代码具有良好的移植性，则不应分配128KB以上的内存。
kmalloc以及get_free_page等分配的内存在物理内存中也是连续的。kmalloc以及get_free_page使用的（虚拟）地址范围与物理内存是一一对应的，可能会有基于```PAGE_OFFSET```的一个偏移。他们不需要为该地址修改页表。

**vmalloc**分配的地址是不能在微处理器以外的地方使用的。当驱动程序需要真正的物理地址（如外设用以驱动系统总线的DMA地址），就不能使用vmalloc了。使用vmalloc的正确场合是在分配一大块连续的，只在软件中存在的，用于缓冲的内存区域的时候。vmalloc比__get_free_pages开销大，因为他不仅获取内存，还要建立页表。

**ioremap**和vmalloc都会修改页表。ioremap不实际分配内存，ioremap更多用于映射（物理的）PCI缓存区地址到（虚拟的）内核空间。

---
# 与硬件通信
An rmb/wmb (read/write memory barrier) guarantees that any reads/writes appearing before the barrier are completed prior to the execution of any subsequent read/write.
```
#include <asm/system.h>
void rmb(void);
void wmb(void);
void mb(void);
```
## Using I/O port
All I/O Port allocation can be read from ```/proc/ioports```
```
#include <linux/ioport.h>
struct resource *request_region(unsigned long first, unsigned long n, 
                                const char *name);
void release_region(unsigned long start, unsigned long n);
unsigned inb(unsigned port);
void outb(unsigned char byte, unsigned port);
unsigned inw(unsigned port);
void outw(unsigned short word, unsigned port);
unsigned inl(unsigned port);
void outl(unsigned longword, unsigned port);
```
## Using I/O memory
All I/O memory allocation can be read from ```/proc/iomem```
Depending on the computer platform and bus being used, I/O memory may or may not be accessed through page tables. When access passes though page tables, the kernel must first arrange for the physical address to be visible from your driver, and this usually means that you must call ```ioremap``` before doing any I/O. If no page tables are needed, I/O memory locations look pretty much like I/O ports, and you can just read and write to them using proper wrapper functions.
```
struct resource *request_mem_region(unsigned long start, unsigned long len,
                                    char *name);
void release_mem_region(unsigned long start, unsigned long len);
```
Allocation of I/O memory is not the only required step before that memory may be accessed. You must also ensure that this I/O memory has been made accessible to the kernel. Getting at I/O memory is not just a matter of dereferencing a pointer; on many systems, I/O memory is not directly accessible in this way at all. So a mapping must be set up first.
**Once equipped with ioremap (and iounmap), a device driver can access any I/O memory address, whether or not it is directly mapped to virtual address space. **Remember, though, that the addresses returned from ioremap should not be dereferenced directly; instead, accessor functions provided by the kernel should be used.
```
#include <asm/io.h>
void *ioremap(unsigned long phys_addr, unsigned long size);
void *ioremap_nocache(unsigned long phys_addr, unsigned long size); //use this one, though it is the same as ioremap on many platforms.
void iounmap(void * addr);
// 以下函数还有16 32的版本
unsigned int ioread8(void *addr); 
void iowrite8(u8 value, void *addr);
void ioread8_rep(void *addr, void *buf, unsigned long count); // Note that 'count' is expressed in the size of the data being written; ioread32_rep reads 'count' 32-bit values starting at buf.
```
### Ports as I/O Memory
This function remaps ```count``` I/O ports and makes them appear to be I/O memory. From that point thereafter, the driver may use ioread8 and friends on the returned addresses and forget that it is using I/O ports at all.  
These functions make I/O ports look like memory. Do note, however, that the I/O ports must still be allocated with request_region before they can be remapped in this way.
```
void *ioport_map(unsigned long port, unsigned int count);
void ioport_unmap(void *addr);
```
---
# 中断
SA_INTERRUPT标记快速中断，快速中断运行时禁止当前处理器上的其他中断(这是由调用中断服务程序的代码完成的)。在现代操作系统中只有少数几种特殊情况（如定时器中断）下使用。
没有SA_INTERRUPT标记的中断在运行时，硬件中断会被重新打开(这是由调用中断服务程序的代码完成的)，同时调用中断服务程序。
- 顶半部处理例程和底半部处理例程最大的区别，就是当底半部处理例程执行时，所有的中断都是打开的--这就是所谓的更安全时间内运行。
- 典型的情况是顶半部保存设备的数据到一个设备特定的缓存区并调度它的底半部，然后退出。（例如：当一个网络接口报告有新的数据包到来时，处理例程仅仅接收数据并把它推到协议层上，而实际的数据处理是在底半部进行的）
- **tasklet**是优选的底半部实现方式，因为这种机制非常快，但它要求代码必须是原子的。
    - tasklet可以确保和第一次调度它们的函数运行在同样的CPU上。这样，tasklet在中断例程结束前并不会开始运行，所以此时的中断例程是安全的。
    - 不管怎样，在tasklet运行时，当然可以有其他中断发生，因此在tasklet和中断处理例程之间的锁还是需要的。
    - 一些中断可以在很短的时间内发生很多次，所以在底半部被之执行前，肯定会有多次中断发生。驱动程序必须对这种情况有所准备，并且根据顶半部保留的信息知道底半部运行时有多少任务要做。
- **工作队列**是另一种底半部的实现方式，它可以具有更高的延时，但允许休眠。
    - 可以使用系统默认的工作队列。但是，如果我们的驱动函数有特殊的延时要求（在工作队列函数中长时间休眠），则应该创建我们自己的专用工作队列。   

## 共享中断
- 共享中断也通过```request_irq()```安装，但有两处不同：
    - 必须指定flags参数中的SA_SHIRQ位。
    - dev_id必须是唯一的。任何指向模块地址空间的指针都可以使用。但不能设置成NULL。
- 内核为每个中断维护了一个共享处理例程列表，这些处理例程的dev_id各不相同，就像是设备的签名。如果两个驱动程序在同一个中断上都注册NULL作为它们的签名，那么在卸载的时候引起混淆，在中断到达的时候内核出现oops消息。
- 当请求一个共享中断时，满足以下两个条件之一，那么```request_irq()```就会成功：
    - 中断信号线空闲。
    - 任何已经注册了该中断信号线的处理例程也标识了IRQ是共享的。
- 不能使用```enable_irq```和```disable_irq```
- 当中断来临时，所有已注册的处理例程都会被调用。一个共享中断例程必须能够将要处理的中断和其它设备产生的中断区分开来。通常一个真正的驱动程序或许会用dev_id参数来判断产生中断的某个或多个设备。需要注意的是，并不是所有设备都能区分中断的，这些设备要求独占中断线。比如打印机协议不允许共享中断，而且它的驱动程序无从知道中断是否由打印机产生。

---
**Tasklets** offer a number of interesting features:
- A tasklet can be disabled and re-enabled later; it won't be executed until it is enabled as many times as it has been disabled.
- Just like timers, a tasklet can reregister itself.
- A tasklet can be scheduled to execute at normal priority or high priority. The latter group is always executed first.
- Tasklets may be run immediately if the system is not under heavy load but never later than the next timer tick.
- A tasklets can be concurrent with other tasklets but is strictly serialized with respect to itself—the same tasklet never runs simultaneously on more than one processor. Also, as already noted, a tasklet always runs on the same CPU that schedules it.  

- tasklet也在“软件中断”上下文以原子模式执行，软件中断是打开硬件中断的同时执行某些异步任务的一种内核机制。
- 它们可以被多次调用，但调用不会累积，也就是说实际值运行一次。不会有同一tasklet的多个实例并行的允许，因为它只运行一次。
- tasklet可以和其它的tasklet并行的运行在对称多处理器 （SMP）系统上。这样，如果驱动程序有多个tasklet，它们应该使用某种锁机制来避免冲突。

---
**workqueue**工作队列
- struct workqueue_struct 工作队列，struct work_struct 工作。
- 每个工作队列有一个或多个专用的进程（“内核线程”），这些进程运行提交到该队列的函数。如果我们使用```create_workqueue()```，则会在系统的每个处理器上都创建一个该工作队列的专用线程。在多数情况 下，如果单个线程足够使用，应该使用```create_singlethread_workqueue()```来创建工作队列。
- ```queue_work(struct workqueue_struct *queue, struct work_struct *work)```把工作加入指定工作队列。
- ```schedule_work(struct work_struct *work)```把工作加入系统默认工作队列。
- 工作队列的默认行为是，始终运行在被初始提交的处理器上。

---
所有模块都需要包含：
```
#include <linux/module.h> //必须的头文件
#include <linux/init.h>
    MODULE_LICENSE("GPL");
```
---
用EXPORT_SYMBOL(name); 和EXPORT_SYMBOL_GPL(name); 两个宏来将给定的符号导出到模块外部。这两个宏将被拓展成一个特殊变量的声明，且改变量必须是全局的。该变量将在模块可执行文件的特殊部分(即一个“ELF段")中保持，在加载模块时，内核通过这个段来寻找需要导出的变量。

---
公共内核符号表中包含了所有的全局内核（即函数和变量）的地址，当模块被装入内核后，它所导出的任何符号都会变成内核符号表的一部分。

---
双下划线前缀API通常是接口的底层组件，表示“谨慎使用，否则后果自负。”

---
应用程序退出时，可以不管资源的释放或者其他的清除工作，但模块的退出函数却必须仔细撤销初始化函数所做的一切，否则，住系统重新引导之前某系东西就会残留在系统中。

---
想要为2.6.x的内核构造模块，必须在自己的系统中配置并构造好内核树。只要求和先前本版的内核不同，先前的内核只需要有一套内核头文件就够了。但2.6内核的模块要和内核源代码树中的目标文件连接，以便能获得一个更加健壮的模块装载器。

---

# down_interruptable  

```down_interruptable```它允许等在某个信号量上的用户空间进能 被**用户信号**中断（而不是产生一个不可杀死的进程）。这是我们总是要用的down版本。   
```down```把等待信号量的进程置于不可杀死状态（ps输出的D state），这会使用户十分懊恼。  
```down_trylock```永远不会休眠，信号量不可获得时，立即返回一个非零值。  

---

---
设置设备为不不可seek，两步：
- 1.open系统调用返回时返回```return nonseekable_open(inode, filp);```
- 2.file_operations 结构体成员赋值```.llseek =	no_llseek,```
