// Long-term locks for processes
struct sleeplock
{
  uint locked; // Is the lock held?
  Spinlock lk; // spinlock protecting this sleep lock

  // For debugging:
  char *name; // Name of lock.
  int pid;    // Process holding lock
};
