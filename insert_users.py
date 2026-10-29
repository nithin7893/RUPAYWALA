"""
Script to delete all users and insert 3 users with proper bcrypt hashes.
"""
from app.database import SessionLocal
from app.utils.security import hash_password
from app.models.user import User, UserRole, AccountStatus
from sqlalchemy import delete

db = SessionLocal()
try:
    # Delete all existing users
    db.execute(delete(User))
    db.commit()
    print('Deleted all existing users')

    # Create new users using raw SQL to avoid enum type issues
    import psycopg2
    from app.database import DATABASE_URL
    
    # Parse DATABASE_URL to get connection params
    # postgresql+psycopg2://postgres:Nithin024%40@localhost:5432/rupaywala_ori
    conn = psycopg2.connect(
        host="localhost",
        port=5432,
        database="rupaywala_ori",
        user="postgres",
        password="Nithin024@"
    )
    conn.autocommit = True
    cursor = conn.cursor()
    
    users = [
        ('7095830930', hash_password('admin123'), 'admin'),
        ('9032226441', hash_password('fieldmember123'), 'field_member'),
        ('9652351440', hash_password('customer123'), 'customer'),
    ]
    
    for phone, pwd_hash, role in users:
        cursor.execute(
            "INSERT INTO users (phone_number, password_hash, role, is_verified, account_status, created_at, updated_at) "
            "VALUES (%s, %s, %s::user_role, %s, %s::account_status, NOW(), NOW())",
            (phone, pwd_hash, role, True, 'active')
        )
        print(f'Inserted {role}: {phone}')
    
    cursor.close()
    conn.close()
    print('All users inserted successfully')
    db.commit()
    print('Inserted 3 users successfully')
    print('Admin: 7095830930 / admin123')
    print('Field Member: 9032226441 / fieldmember123')
    print('Customer: 9652351440 / customer123')
finally:
    db.close()
