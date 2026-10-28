/* A header the package binds with `autobind`. */
#define AUTOBIND_BASE 30

enum autobind_kind { AUTOBIND_NONE, AUTOBIND_DISK = 4, AUTOBIND_NET };

typedef struct autobind_point {
    int x;
    int y;
} autobind_point;

struct autobind_record {
    unsigned int flags;
    autobind_point origin;
    char name[8];
};

double cos(double x);
int autobind_missing(void);
