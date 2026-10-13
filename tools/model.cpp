// The reference model of the search of the hardware (src/main/engine.vhd).
//
// It reads the slots of a puzzle (written by tools/model.py from
// tools/puzzles.py), and searches exactly like the hardware: the board is a
// window of W bits starting at the anchor (the lowest empty square), a node
// has the bit vector F of the slots that fit at its anchor, and every pass
// visits one node (the lowest remaining child of the current node). The tree
// is split at the depth D between NCTX contexts, see engine.vhd:
// * every context walks the levels 1 to D (only context 0 counts the nodes
//   above D, and its solutions),
// * the subtree of the j-th node at depth D (counted from 0, in the order of
//   the search) belongs to context j mod NCTX; the other contexts visit the
//   node but skip it (no children, not counted),
// * the root is counted once.
// With NCTX = 1 this is the search of the C++ program, in the same order.
//
// Usage: model <slots file> <command> [args]
//   run <nctx> <depth>         Counts of every context: passes, nodes, solutions
//   trace <nctx> <depth> <ctx> <n>
//                              The first n passes of the context, one per
//                              line: level of the child, anchor, slot, flags
//   firsts <nctx> <depth>      For each context the number of passes until
//                              (and including) its first solution, 0 if none
//   solutions <n>              The first n solutions (NCTX = 1), as boards
//   subtrees <maxdepth>        For each depth up to maxdepth: the number of
//                              nodes, and the size of the subtree of each
//                              node (in the order of the search), see
//                              model.py (choosing the depth)
//   frontier <depth>           The number of nodes at the depth (a search
//                              that stops at that depth)

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

// The search of one context. The callback is called for every pass, with the
// level of the visited child, the child, whether it is counted, skipped, and
// a solution. It returns false to stop the search.
struct Pass
{
   int  level;     // Of the visited child (1 to num_pieces)
   int  anchor;    // Of the parent, i.e. where the child's piece is placed
   int  slot;
   bool counted;
   bool skipped;
   bool solution;
};

template <class F>
static void search(int nctx, int depth, int ctx, F callback)
{
   std::vector<Node> stack(num_pieces + 1);
   stack[0].base = 0;
   stack[0].win.reset();
   stack[0].used = 0;
   stack[0].f = children(0, stack[0].win, 0);
   int level = 0;
   long j = 0;  // The number of nodes at the depth so far
   if (stack[0].f.none())
      return;
   while (true)
   {
      Node &n = stack[level];
      int k = n.f._Find_first();
      n.f.reset(k);
      n.slot = k;
      // The child
      window_t c = n.win | slots[k].mask;
      int t = (~c)._Find_first();
      Node &child = stack[level + 1];
      child.win = c >> t;
      child.base = n.base + t;
      child.used = n.used | (1u << slots[k].piece);
      int lvl = level + 1;
      Pass p;
      p.level = lvl;
      p.anchor = n.base;
      p.slot = k;
      p.skipped = false;
      if (lvl == depth)
      {
         p.skipped = (j % nctx) != ctx;
         ++j;
      }
      p.counted = lvl < depth ? ctx == 0 : !p.skipped;
      p.solution = p.counted && lvl == num_pieces && child.base == squares;
      if (!p.skipped && lvl < num_pieces)
         child.f = children(child.base, child.win, child.used);
      else
         child.f.reset();
      if (!callback(p, stack))
         return;
      if (child.f.any())
         level = lvl;
      else
      {
         while (level >= 0 && stack[level].f.none())
            --level;
         if (level < 0)
            return;
      }
   }
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

   if (cmd == "run" && argc == 5)
   {
      int nctx = atoi(argv[3]), depth = atoi(argv[4]);
      long tot_nodes = 1, tot_sol = 0, max_passes = 0;
      for (int x = 0; x < nctx; ++x)
      {
         long passes = 0, nodes = 0, sol = 0;
         search(nctx, depth, x, [&](const Pass &p, const std::vector<Node> &) {
            ++passes;
            nodes += p.counted;
            sol += p.solution;
            return true;
         });
         printf("ctx %d passes %ld nodes %ld solutions %ld\n", x, passes, nodes, sol);
         tot_nodes += nodes;
         tot_sol += sol;
         if (passes > max_passes)
            max_passes = passes;
      }
      printf("total nodes %ld solutions %ld max_passes %ld\n", tot_nodes, tot_sol, max_passes);
   }
   else if (cmd == "trace" && argc == 7)
   {
      int nctx = atoi(argv[3]), depth = atoi(argv[4]), ctx = atoi(argv[5]);
      long n = atol(argv[6]), i = 0;
      search(nctx, depth, ctx, [&](const Pass &p, const std::vector<Node> &) {
         printf("%d %d %d %d %d %d\n", p.level, p.anchor, p.slot, p.counted, p.skipped,
                p.solution);
         return ++i < n;
      });
   }
   else if (cmd == "firsts" && argc == 5)
   {
      int nctx = atoi(argv[3]), depth = atoi(argv[4]);
      for (int x = 0; x < nctx; ++x)
      {
         long i = 0, first = 0;
         search(nctx, depth, x, [&](const Pass &p, const std::vector<Node> &) {
            ++i;
            if (p.solution)
            {
               first = i;
               return false;
            }
            return true;
         });
         printf("%ld\n", first);
      }
   }
   else if (cmd == "solutions" && argc == 4)
   {
      long n = atol(argv[3]), i = 0;
      search(1, 1, 0, [&](const Pass &p, const std::vector<Node> &stack) {
         if (!p.solution)
            return true;
         std::vector<int> board(squares, -1);
         for (int l = 0; l < p.level; ++l)
            for (int o : slots[stack[l].slot].offsets)
               board[stack[l].base + o] = slots[stack[l].slot].piece;
         for (int r = 0; r < rows; ++r)
         {
            for (int c = 0; c < cols; ++c)
               printf("%2d ", board[r * cols + c]);
            printf("\n");
         }
         printf("\n");
         return ++i < n;
      });
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
         // Close the open nodes at lvl and below
         for (int l = num_pieces + 1; l >= lvl; --l)
            if (open[l])
            {
               if (l <= maxdepth)
                  sizes[l].push_back(count - start[l]);
               open[l] = 0;
            }
      };
      search(1, 1, 0, [&](const Pass &p, const std::vector<Node> &) {
         close(p.level);
         open[p.level] = 1;
         start[p.level] = count;
         ++count;
         return true;
      });
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
      // A search that does not go below the depth: context -1 skips every
      // node at the depth.
      int depth = atoi(argv[3]);
      long n = 0;
      search(1, depth, -1, [&](const Pass &p, const std::vector<Node> &) {
         n += p.level == depth;
         return true;
      });
      printf("frontier %ld\n", n);
   }
   else
   {
      std::cerr << "Unknown command or wrong arguments, see model.cpp" << std::endl;
      return 1;
   }
   return 0;
}
