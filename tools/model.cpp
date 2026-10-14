// The reference model of the search of the hardware (src/main/engine.vhd and
// src/main/solver.vhd).
//
// It reads the slots of a puzzle (written by tools/model.py from
// tools/puzzles.py), and searches exactly like the hardware: the board is a
// window of W bits starting at the anchor (the lowest empty square), a node
// has the bit vector F of the slots that fit at its anchor, and every pass
// visits one node (the lowest remaining child of the current node).
//
// The tree is split at the depth D between the contexts: E engines with 8
// contexts each, numbered g = 8 * engine + id. Every context walks the tree
// down to the depth D (only context 0 counts the nodes above D, and their
// solutions; the root is counted once). The nodes at depth D are numbered
// j = 0, 1, ... in the order of the search, and each context has a target:
// it owns (searches) the subtree of node j when j is its target, and skips
// the other nodes at depth D (visits them, but gives them no children, and
// does not count them). When a context owns a node, it claims a new target
// from a global counter. At the start, the target of context g is g, and the
// counter is the number of contexts.
//
// The contexts are stepped one pass at a time in the order of the hardware:
// in each round, the contexts with id 0 to 7, and for each id the engines 0
// to E-1 (the engines commit the same id in the same clock cycle, and the
// claims of one clock cycle are granted in the order of the engines). So the
// claims, and the traces, are exactly those of the hardware, when it runs
// freely (run_i high all the time). The command "seq" is one context without
// a split, i.e. the search of the C++ program, in the same order.
//
// Usage: model <slots file> <command> [args]
//   run <engines> <depth>      Counts of every context: passes, nodes,
//                              solutions, and the totals
//   trace <engines> <depth> <prefix> [<passes>]
//                              Writes every pass of every context g to
//                              <prefix>_<g>.trace, one per line: level of the
//                              child, anchor, slot, counted, skipped, solution.
//                              With <passes>, only the first passes of each
//                              context, and the search stops when every
//                              context has made them (for 16x16)
//   firsts <engines> <depth>   For each context the number of passes until
//                              (and including) its first solution, 0 if none
//   seq                        One context (the C++ program): the counts
//   solutions <n>              The first n solutions of "seq", as boards
//   subtrees <maxdepth>        For each depth up to maxdepth: the number of
//                              nodes, and the size of the subtree of each
//                              node (in the order of the search)
//   frontier <depth>           The number of nodes at the depth

#include <bitset>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

typedef std::bitset<192> window_t;   // Must be more than the widest window (129)
typedef std::bitset<160> fvec_t;     // Must be at least the number of slots (152)

struct Slot
{
   int piece;
   int down, left, right;
   std::vector<int> offsets;
   window_t mask;
};

static int rows, cols, squares, num_pieces, num_slots, width;
static std::vector<Slot> slots;
static std::vector<fvec_t> valid;     // Slots inside the board, for each anchor
static std::vector<fvec_t> of_piece;  // Slots of each piece

static void read_slots(const char *filename)
{
   std::ifstream f(filename);
   if (!f)
   {
      std::cerr << "Cannot open " << filename << std::endl;
      exit(1);
   }
   f >> rows >> cols >> num_pieces >> num_slots >> width;
   squares = rows * cols;
   if (width > (int) window_t().size() || num_slots > (int) fvec_t().size())
   {
      std::cerr << "The window or the number of slots is too large" << std::endl;
      exit(1);
   }
   slots.resize(num_slots);
   of_piece.resize(num_pieces);
   for (int k = 0; k < num_slots; ++k)
   {
      Slot &s = slots[k];
      int n;
      f >> s.piece >> s.down >> s.left >> s.right >> n;
      s.offsets.resize(n);
      for (int i = 0; i < n; ++i)
      {
         f >> s.offsets[i];
         s.mask.set(s.offsets[i]);
      }
      of_piece[s.piece].set(k);
   }
   valid.resize(squares);
   for (int a = 0; a < squares; ++a)
   {
      int r = a / cols, c = a % cols;
      for (int k = 0; k < num_slots; ++k)
      {
         const Slot &s = slots[k];
         if (r + s.down < rows && c - s.left >= 0 && c + s.right < cols)
            valid[a].set(k);
      }
   }
}

// A node of the search: the anchor (base), the window, the pieces used, and
// the slots that fit (the children not visited yet)
struct Node
{
   int      base;
   window_t win;
   uint32_t used;
   fvec_t   f;
   int      slot;  // The slot of the child visited last
};

// The slots that fit at a node, i.e. its children
static fvec_t children(int base, const window_t &win, uint32_t used)
{
   fvec_t f;
   if (base >= squares)
      return f;
   fvec_t cand = valid[base];
   for (int b = 0; b < num_pieces; ++b)
      if (used & (1u << b))
         cand &= ~of_piece[b];
   for (int k = cand._Find_first(); k < num_slots; k = cand._Find_next(k))
      if ((win & slots[k].mask).none())
         f.set(k);
   return f;
}

// One pass
struct Pass
{
   int  level;     // Of the visited child (1 to num_pieces)
   int  anchor;    // Of the parent, i.e. where the child's piece is placed
   int  slot;
   bool counted;
   bool skipped;
   bool solution;
};

// A search context
struct Context
{
   int               gid;     // Global number
   std::vector<Node> stack;
   int               level;   // Of the current node
   long              j;       // Nodes at depth D so far
   long              target;  // The node at depth D to search next
   bool              done;
   long              passes, nodes, solutions, first;

   explicit Context(int g) :
      gid(g), stack(num_pieces + 1), level(0), j(0), target(g), done(false),
      passes(0), nodes(0), solutions(0), first(0)
   {
      stack[0].base = 0;
      stack[0].win.reset();
      stack[0].used = 0;
      stack[0].f = children(0, stack[0].win, 0);
      done = stack[0].f.none();
   }

   // One pass. With a depth of 0 there is no split (one context). A claim
   // takes the next target from the counter.
   Pass step(int depth, long &counter)
   {
      Node &n = stack[level];
      int k = n.f._Find_first();
      n.f.reset(k);
      n.slot = k;
      window_t c = n.win | slots[k].mask;
      int t = (~c)._Find_first();
      Node &child = stack[level + 1];
      child.win = c >> t;
      child.base = n.base + t;
      child.used = n.used | (1u << slots[k].piece);
      Pass p;
      p.level = level + 1;
      p.anchor = n.base;
      p.slot = k;
      p.skipped = false;
      if (p.level == depth)
      {
         bool owned = j == target;
         p.skipped = !owned;
         ++j;
         if (owned)
            target = counter++;
      }
      p.counted = p.level < depth ? gid == 0 : !p.skipped;
      p.solution = p.counted && p.level == num_pieces && child.base == squares;
      if (!p.skipped && p.level < num_pieces)
         child.f = children(child.base, child.win, child.used);
      else
         child.f.reset();
      if (child.f.any())
         level = p.level;
      else
      {
         while (level >= 0 && stack[level].f.none())
            --level;
         if (level < 0)
            done = true;
      }
      ++passes;
      nodes += p.counted;
      solutions += p.solution;
      if (p.solution && first == 0)
         first = passes;
      return p;
   }
};

// The search of all the contexts, in the order of the hardware. The callback
// gets every pass.
template <class F>
static std::vector<Context> search(int engines, int depth, F callback)
{
   std::vector<Context> ctx;
   for (int g = 0; g < 8 * engines; ++g)
      ctx.emplace_back(g);
   long counter = 8 * engines;
   bool busy = true;
   while (busy)
   {
      busy = false;
      for (int id = 0; id < 8; ++id)
         for (int e = 0; e < engines; ++e)
         {
            Context &x = ctx[8 * e + id];
            if (x.done)
               continue;
            busy = true;
            Pass p = x.step(depth, counter);
            callback(x, p);
         }
   }
   return ctx;
}

int main(int argc, char **argv)
{
   if (argc < 3)
   {
      std::cerr << "Usage: model <slots file> <command> [args], see model.cpp" << std::endl;
      return 1;
   }
   read_slots(argv[1]);
   std::string cmd = argv[2];

   if ((cmd == "run" || cmd == "firsts") && argc == 5)
   {
      int engines = atoi(argv[3]), depth = atoi(argv[4]);
      auto ctx = search(engines, depth, [](const Context &, const Pass &) {});
      long nodes = 1, sol = 0, max_passes = 0;
      for (const Context &x : ctx)
      {
         if (cmd == "run")
            printf("ctx %d passes %ld nodes %ld solutions %ld\n", x.gid, x.passes, x.nodes,
                   x.solutions);
         else
            printf("%ld\n", x.first);
         nodes += x.nodes;
         sol += x.solutions;
         if (x.passes > max_passes)
            max_passes = x.passes;
      }
      if (cmd == "run")
         printf("total nodes %ld solutions %ld max_passes %ld\n", nodes, sol, max_passes);
   }
   else if (cmd == "trace" && (argc == 6 || argc == 7))
   {
      int engines = atoi(argv[3]), depth = atoi(argv[4]);
      long limit = argc == 7 ? atol(argv[6]) : -1;
      std::vector<long> written(8 * engines, 0);
      int full = 0;  // Contexts that have written limit passes
      struct Stop
      {
      };
      std::vector<FILE *> f;
      for (int g = 0; g < 8 * engines; ++g)
      {
         std::string name = std::string(argv[5]) + "_" + std::to_string(g) + ".trace";
         f.push_back(fopen(name.c_str(), "w"));
         if (!f.back())
         {
            std::cerr << "Cannot write " << name << std::endl;
            return 1;
         }
      }
      try
      {
         search(engines, depth, [&](const Context &x, const Pass &p) {
            if (limit >= 0 && written[x.gid] >= limit)
               return;
            fprintf(f[x.gid], "%d %d %d %d %d %d\n", p.level, p.anchor, p.slot, p.counted,
                    p.skipped, p.solution);
            if (++written[x.gid] == limit && ++full == 8 * engines)
               throw Stop();
         });
      }
      catch (const Stop &)
      {
      }
      for (FILE *fp : f)
         fclose(fp);
   }
   else if (cmd == "seq" && argc == 3)
   {
      Context x(0);
      long counter = 1;
      while (!x.done)
         x.step(0, counter);
      printf("total nodes %ld solutions %ld max_passes %ld\n", x.nodes + 1, x.solutions,
             x.passes);
   }
   else if (cmd == "solutions" && argc == 4)
   {
      long n = atol(argv[3]), i = 0;
      Context x(0);
      long counter = 1;
      while (!x.done && i < n)
      {
         Pass p = x.step(0, counter);
         if (!p.solution)
            continue;
         std::vector<int> board(squares, -1);
         for (int l = 0; l < p.level; ++l)
            for (int o : slots[x.stack[l].slot].offsets)
               board[x.stack[l].base + o] = slots[x.stack[l].slot].piece;
         for (int r = 0; r < rows; ++r)
         {
            for (int c = 0; c < cols; ++c)
               printf("%2d ", board[r * cols + c]);
            printf("\n");
         }
         printf("\n");
         ++i;
      }
   }
   else if (cmd == "subtrees" && argc == 4)
   {
      // The size of the subtree of every node down to maxdepth: a node's size
      // is known when the search leaves it, i.e. at the next pass at its
      // level or above, so the open nodes are kept on a stack.
      int maxdepth = atoi(argv[3]);
      std::vector<std::vector<long>> sizes(maxdepth + 1);
      std::vector<long> start(num_pieces + 2, 0);
      std::vector<int> open(num_pieces + 2, 0);
      long count = 1;  // Nodes visited so far, including the root
      auto close = [&](int lvl) {
         for (int l = num_pieces + 1; l >= lvl; --l)
            if (open[l])
            {
               if (l <= maxdepth)
                  sizes[l].push_back(count - start[l]);
               open[l] = 0;
            }
      };
      Context x(0);
      long counter = 1;
      while (!x.done)
      {
         Pass p = x.step(0, counter);
         close(p.level);
         open[p.level] = 1;
         start[p.level] = count;
         ++count;
      }
      close(1);
      printf("nodes %ld\n", count);
      for (int d = 1; d <= maxdepth; ++d)
      {
         printf("depth %d %zu", d, sizes[d].size());
         for (long s : sizes[d])
            printf(" %ld", s);
         printf("\n");
      }
   }
   else if (cmd == "frontier" && argc == 4)
   {
      // A context whose target is never reached skips every node at the
      // depth, so it only walks the tree above it.
      int depth = atoi(argv[3]);
      Context x(0);
      x.target = -1;
      long counter = 0, n = 0;
      while (!x.done)
         n += x.step(depth, counter).level == depth;
      printf("frontier %ld\n", n);
   }
   else
   {
      std::cerr << "Unknown command or wrong arguments, see model.cpp" << std::endl;
      return 1;
   }
   return 0;
}
