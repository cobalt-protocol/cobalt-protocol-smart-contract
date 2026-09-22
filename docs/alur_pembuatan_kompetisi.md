# Alur Pembuatan Kompetisi (Competition Creation Flow)

Dokumen ini menjelaskan alur lengkap pembuatan kompetisi pada **Cobalt Protocol**, mulai dari prasyarat sistem, penyiapan konfigurasi JSON, hingga alur eksekusi internal pada smart contract `CompetitionManager`.

---

## 1. Ikhtisar (Overview)

Pembuatan kompetisi di Cobalt Protocol dikelola oleh smart contract `CompetitionManager.sol`. Ketika sebuah organisasi membuat kompetisi, sistem akan:
1. Memvalidasi opsi fee platform yang dipilih.
2. Memvalidasi bahwa token hadiah (*prize token*) telah terdaftar dan aktif.
3. Membayar fee platform ke `TreasuryPlatform`.
4. Mengunci (*lock*) seluruh total dana hadiah ke `TreasuryPrize`.
5. Menyimpan data kompetisi & daftar pemenang on-chain serta memancarkan event `CompetitionCreated`.

---

## 2. Prasyarat (Prerequisites)

Sebelum membuat kompetisi, pastikan prasyarat berikut telah terpenuhi:

1. **Platform Fee Option Terdaftar**
   - Pemilik (*Owner*) platform telah menambahkan opsi fee pada `PriceCompetitionManager`. Setiap opsi fee memiliki `platformFeeId`.
2. **Token Hadiah Terdaftar**
   - Token yang digunakan sebagai hadiah (*prize token*) harus sudah didaftarkan dan aktif pada `ListingTokenPrizeContract`.
   - Untuk Native Token (misalnya ETH/BotChain Native), gunakan alamat `0x0000000000000000000000000000000000000000`.
3. **Keterbatasan Token Hadiah**
   - Seluruh pemenang dalam satu kompetisi **harus menggunakan jenis token hadiah yang sama** (*uniform prize token*).
4. **Saldo & Allowance (Persetujuan Transfer)**
   - Jika fee platform atau token hadiah menggunakan **Native Token**, pembuat kompetisi harus mengirimkan ETH/Native token yang cukup melalui `msg.value` (`msg.value = treasuryFee + totalPrizeAmount`).
   - Jika menggunakan **ERC20 Token**, akun pembuat kompetisi harus memberikan `approve` allowance kepada kontrak `TreasuryPlatform` (untuk fee) dan `TreasuryPrize` (untuk hadiah).

---

## 3. Format File Konfigurasi (JSON)

Pembuatan kompetisi disarankan menggunakan file konfigurasi JSON (contoh: `scripts/competitions/example_competition.json`):

```json
{
  "competition": {
    "name": "Web3 Hackathon 2026",
    "category": "Hackathon",
    "description": "Build innovative dApps using blockchain technology.",
    "requirements": "Open for all developers",
    "durationInSeconds": 86400,
    "certificateCID": "QmCertificateCID123",
    "guideBookCID": "QmGuideBookCID123",
    "platformFeeId": 1
  },
  "winners": [
    {
      "title": "1st Place",
      "prizeToken": "0x0000000000000000000000000000000000000000",
      "prizeAmount": 0.05,
      "certificateCID": "QmWinnerCertCID123"
    },
    {
      "title": "2nd Place",
      "prizeToken": "0x0000000000000000000000000000000000000000",
      "prizeAmount": 0.03,
      "certificateCID": "QmWinnerCertCID456"
    }
  ]
}
```

### Penjelasan Field:
- **`name`**: Nama kompetisi.
- **`category`**: Kategori kompetisi (misal: Hackathon, UI/UX, Security).
- **`description`**: Deskripsi kompetisi.
- **`requirements`**: Persyaratan peserta.
- **`durationInSeconds` / `durationInDays`**: Durasi kompetisi dari waktu eksekusi transaksi.
- **`certificateCID`**: IPFS CID sertifikat kepesertaan umum.
- **`guideBookCID`**: IPFS CID buku panduan kompetisi.
- **`platformFeeId`**: ID opsi fee platform yang dipilih dari `PriceCompetitionManager`.
- **`winners`**: Array pemenang (judul, token hadiah, jumlah hadiah, IPFS CID sertifikat pemenang).


---

## 4. Langkah-Langkah Eksekusi

### Langkah A: Menggunakan Ape Helper Script (Rekomendasi)

Jalankan perintah berikut pada terminal:

```bash
ape run competitions create_competition <ACCOUNT_NAME> <INPUT_JSON_PATH> --network <NETWORK>
```

**Contoh:**
```bash
ape run competitions create_competition organization scripts/competitions/example_competition.json --network bot_chain:bot_chain_test_net:node
```

Script `create_competition.py` secara otomatis akan:
1. Membaca konfigurasi JSON.
2. Mengecek status fee dari `PriceCompetitionManager`.
3. Menghitung jadwal timestamp berdasarkan durasi.
4. Melakukan `approve` otomatis pada token ERC20 jika dibutuhkan.
5. Menghitung total `msg.value` yang diperlukan dan memanggil fungsi `createCompetition` pada smart contract.

---

### Langkah B: Eksekusi Langsung via Smart Contract (`CompetitionManager.sol`)

Fungsi utama pada smart contract `CompetitionManager.sol`:

```solidity
function createCompetition(
    Competitions calldata _competition,
    Winners[] calldata _winners,
    uint256 _priceCompetitionFeeId
) external payable
```

#### Alur Eksekusi Internal Smart Contract:
1. **Validasi End Time**:
   `require(_competition.schedule.prizeCertificateClaim > block.timestamp, "Invalid end time");`
2. **Validasi Pemenang**:
   `require(_winners.length > 0, "Must have at least one winner");`
3. **Pendaftaran & Validasi Hadiah**:
   - Memastikan setiap token hadiah terdaftar dan aktif di `ListingTokenPrizeContract`.
   - Menghitung `totalPrizeAmount`.
4. **Pembayaran Fee Platform**:
   - Jika fee Native: Mengirim ETH ke `TreasuryPlatform.addTreasuryFrom`.
   - Jika fee ERC20: Mentransfer token ERC20 dari organisasi ke `TreasuryPlatform`.
5. **Penyetoran Hadiah ke Treasury**:
   - Menyimpan seluruh total hadiah ke `TreasuryPrize`.
6. **Emisi Event**:
   - Memancarkan event `CompetitionCreated(...)` dan `CompetitionFeePaid(...)`.

---

## 5. Verifikasi Kompetisi yang Berhasil Dibuat

Setelah transaksi berhasil, Anda dapat mengonfirmasi data kompetisi melalui perintah berikut:

1. **Melihat Detail Kompetisi:**
   ```bash
   ape run competitions get_competition <ACCOUNT_NAME> <COMPETITION_ID> --network <NETWORK>
   ```

2. **Melihat Daftar Pemenang:**
   ```bash
   ape run competitions get_winners <ACCOUNT_NAME> <COMPETITION_ID> --network <NETWORK>
   ```

3. **Mengecek Status Akhir Kompetisi:**
   ```bash
   ape run competitions is_competition_ended <ACCOUNT_NAME> <COMPETITION_ID> --network <NETWORK>
   ```
