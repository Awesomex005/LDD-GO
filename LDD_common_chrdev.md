###### 常用头文件
```
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/init.h>
#include <linux/kernel.h> /* printk() */
#include <linux/slab.h>  /* kmalloc() */
#include <linux/fs.h>  /* everything... */
#include <linux/errno.h> /* error codes */
#include <linux/types.h> /* size_t */
#include <linux/proc_fs.h>
#include <linux/fcntl.h> /* O_ACCMODE */
#include <linux/seq_file.h>
#include <linux/cdev.h>
#include <asm/uaccess.h> /* copy_*_user */
```
 
# 注册设备
### 1 register_chrdev_region() or alloc_chrdev_region()
- 它们的最后一个参数确定驱动程序的名字（出现在```/proc/devices```中）
 
### 2 cdev_init() and cdev_add()
- ```void cdev_init(struct cdev *cdev, struct file_operations *fops);```
- ``` cdev.owner = THIS_MODULE;```
- ```cdev.ops = &fops;```
- ```int cdev_add(struct cdev *dev, dev_t num, unsigned int count);```
##### 传统的方法使用 register_chrdev
```
int register_chrdev(unsigned int major, const char *name,
                    struct file_operations *fops);
```
### 3 cdev_del() 
### 4 unregister_chrdev_region()
# 编写设备操作
### 5 open
- Check for device-specific errors (such as device-not-ready or similar hardware problems)
- Initialize the device if it is being opened for the first time
- Update the f_op pointer, if necessary
- Allocate and fill any data structure to be put in ```filp->private_data```
 
### 6 close
- Deallocate anything, such as open allocated in ```filp->private_data```
- Shut down the device on last close

### 7 read
- 返回值等于read系统调用的count参数，表明成功。
- 返回值为小于count的正数，表示读了部分数据。大部分情况下程序会继续调用read读完剩下的内容，如fread的库函数，它会不断调用系统调用直到数据传输完毕。
- 返回0，表示到达文件尾。
- 负值表示发生了错误。
- 使用```copy_to_user( )```，
    - 该函数还能检查用户空间内存是否有效，指针无效不拷贝。```__copy_to_user```不检查内存有效性。
    - 当被寻址的用户空间的页面不在内存而在交换区中，虚拟内存子系统会将该进程转入睡眠状态，直到该页面被换如内存。
- 使用```semaphore```或```mutex```保证资源互斥访问。
 
### 8 write
- 使用```copy_from_user( )```
- 使用```semaphore```或```mutex```保证资源互斥访问。
 
 
---
 
---
 
---
 
# semaphore mutex
## semaphore
```
#include <linux/fs.h> // that include <linux/semaphore.h>
struct scull_dev {
    struct scull_qset *data;  /* Pointer to first quantum set */
    int quantum;              /* the current quantum size */
    int qset;                 /* the current array size */
    unsigned long size;       /* amount of data stored here */
    unsigned int access_key;  /* used by sculluid and scullpriv */
    struct semaphore sem;     /* mutual exclusion semaphore     */
    struct cdev cdev;   /* Char device structure  */
};
sema_init(&scull_devices[i].sem, 1);
if (down_interruptible(&dev->sem))
  return -ERESTARTSYS;
up(&dev->sem);
```
- 关于返回```-ERESTARTSYS```，操作被中断的时候返回-ERESTARTSYS，内核高层代码见到-ERESTARTSYS后，要么会重新启动该调用，要么会将错误返回给用户。如果我们在这里返回-ERESTARTSYS，则必须保证撤销了已做的用户可见的操作，这样系统调用可正确重试。否则应返回```-EINTR```。
- ```down_interruptable```它允许等在某个信号量上的用户空间进程被**用户**中断。这是我们总是要用的down版本。```down```把等待信号量的进程置于不可杀死状态（ps输出的D state），这会使用户十分懊恼。```down_trylock```永远不会休眠，信号量不可获得时，立即返回一个非零值


## mutex
```
#include <linux/fs.h> // that include <linux/mutex.h>.
struct scull_dev {
    struct scull_qset *data;  /* Pointer to first quantum set */
    int quantum;              /* the current quantum size */
    int qset;                 /* the current array size */
    unsigned long size;       /* amount of data stored here */
    unsigned int access_key;  /* used by sculluid and scullpriv */
    struct mutex mutex;     /* mutual exclusion semaphore     */
    struct cdev cdev;   /* Char device structure  */
};
mutex_init(&scull_devices[i].mutex);
if (mutex_lock_interruptible(&dev->mutex))
  return -ERESTARTSYS;
  
mutex_unlock(&dev->mutex);
```
 
---
# 调试方式
- printf printk
- strace
- 创建文件到proc文件系统
 ---
# 延时
- 长延时(jiffies/系统时钟中断级别的/毫秒级的)方法参考 jit.c ``` jit_fn_proc_show```（大多数平台每秒有HZ次系统时钟中断，每次时钟中断jiffies加1）
- 细粒度的短延时，它们都是忙等待。
```
#include <linux/delay.h>
void ndelay(unsigned long nsecs);
void udelay(unsigned long usecs);
void mdelay(unsigned long msecs);
```
- 毫秒级（或更长）的延时，非忙等待方法。

```
#include <linux/delay.h>
void msleep(unsigned int millisecs);
unsigned long msleep_interruptible(unsigned int millisecs);
void ssleep(unsigned int seconds);

```

---
# 定时器
参考 jit.c ```jit_timer_proc_show```，内核定时器粒度只能到jiffies。
参考 shortprint.c

---
# tasklet 
参考 jit.c ```jit_tasklet_proc_show```
参考 short.c ```short_tl_interrupt```
​
# workqueue 
参考 jiq.c
参考 short.c ```short_wq_interrupt```
参考 shortprint.c

---
# 基于slab高速缓存的scull: scullc
当需要分配一定量的相同大小的内存块时，可以创建高速缓存内存池，然后从池中分配内存块。
Keyword ```kmem_cache_create```
和scull相比，scullc的主要差别是运行速度略有提高，对内存的利用率更佳。由于数据对象都是从内存池中分配的，而内存池中的内存块都具有相同的大小，所以这些数据对象能以最大密集度排列，相反，scull的数据对象会引入不可预测的内存碎片。
   
---
# 使用整页的scull: scullp
Keyword ```__get_free_pages```
优势在于更有效的使用了内存，按页分配不会浪费内存空间。而用kmalloc则会因分配粒度的原因而浪费一定数量的内存。
 
---
# 与硬件同信 short
---
test commands

```
echo -n xxx > xxx
//read 
dd bs=5 count=1< /dev/short0 2>/dev/null |od -t x1
//write 
echo -n aaa | dd bs=1 count=1 of=/dev/short0 2>/dev/null
```
# 中断 short 
```
#include <linux/sched.h>
int request_irq(unsigned int irq,
                irqreturn_t (*handler)(int, void *, struct pt_regs *),
                unsigned long flags, 
                const char *dev_name,
                void *dev_id);
void free_irq(unsigned int irq, void *dev_id);

//A call to local_irq_save disables interrupt delivery on the current processor after saving the current interrupt state into flags. 
void local_irq_save(unsigned long flags);
void local_irq_disable(void);

void local_irq_restore(unsigned long flags);
void local_irq_enable(void);
```
# 共享中断 short


