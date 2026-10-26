// Test cases for typeorm-sql-injection. Run: scripts/security/sast.sh test
/* eslint-disable */

function bad(repo: any, qb: any, search: string, sort: string) {
  // ruleid: typeorm-sql-injection
  repo.query(`SELECT * FROM notes WHERE title = '${search}'`);

  // ruleid: typeorm-sql-injection
  repo.query("SELECT * FROM notes WHERE title = '" + search + "'");

  // ruleid: typeorm-sql-injection
  qb.where(`note.title ILIKE '%${search}%'`);

  // ruleid: typeorm-sql-injection
  qb.andWhere("note.ownerId = " + search);

  // ruleid: typeorm-sql-injection
  qb.orderBy(`note.${sort}`);
}

function good(repo: any, qb: any, search: string) {
  // ok: typeorm-sql-injection
  repo.query('SELECT * FROM notes WHERE title = $1', [search]);

  // ok: typeorm-sql-injection
  qb.where('note.title ILIKE :term', { term: `%${search}%` });

  // ok: typeorm-sql-injection
  qb.andWhere('note.ownerId = :id', { id: search });
}
