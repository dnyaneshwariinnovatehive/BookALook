'use client';

import { useState, useEffect } from 'react';
import AsyncSelect from 'react-select/async';
import styles from './banners.module.css';

interface Banner {
  id: string;
  title: string;
  image_url: string;
  action_url?: string;
  target_scope: 'platform' | 'city' | 'salon';
  target_city?: string;
  target_salon_id?: string;
  start_date: string;
  end_date: string;
  is_active: boolean;
}

export default function BannersPage() {
  const [banners, setBanners] = useState<Banner[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [editingBannerId, setEditingBannerId] = useState<string | null>(null);
  const [imagePreviewUrl, setImagePreviewUrl] = useState<string | null>(null);
  
  // Filter & Pagination state
  const [filterStatus, setFilterStatus] = useState<string>('');
  const [filterScope, setFilterScope] = useState<string>('');
  const [filterCityId, setFilterCityId] = useState<string>('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [lastPage, setLastPage] = useState<number>(1);
  
  // Form state
  const [title, setTitle] = useState('');
  const [targetScope, setTargetScope] = useState<'platform' | 'city' | 'salon'>('platform');
  const [targetCityId, setTargetCityId] = useState('');
  const [targetSalonId, setTargetSalonId] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [actionUrl, setActionUrl] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);

  const loadCities = async (inputValue: string) => {
    try {
      const res = await fetch(`/api/cities?search=${encodeURIComponent(inputValue)}`);
      if (res.ok) {
        const cities = await res.json();
        return cities.map((city: any) => ({
          label: `${city.name} (${city.state})`,
          value: city.id
        }));
      }
      return [];
    } catch (error) {
      console.error('Failed to load cities', error);
      return [];
    }
  };

  const loadSalons = async (inputValue: string) => {
    try {
      const res = await fetch(`/api/superadmin/salons?search=${encodeURIComponent(inputValue)}`);
      if (res.ok) {
        const salons = await res.json();
        return salons.map((salon: any) => ({
          label: `${salon.name} (${salon.city})`,
          value: salon.id
        }));
      }
      return [];
    } catch (error) {
      console.error('Failed to load salons', error);
      return [];
    }
  };

  useEffect(() => {
    fetchBanners();
  }, [currentPage, filterStatus, filterScope, filterCityId]);

  const fetchBanners = async () => {
    try {
      const queryParams = new URLSearchParams({ page: currentPage.toString() });
      if (filterStatus) queryParams.append('status', filterStatus);
      if (filterScope) queryParams.append('target_scope', filterScope);
      if (filterCityId) queryParams.append('target_city_id', filterCityId);

      const res = await fetch(`/api/superadmin/banners?${queryParams.toString()}`, {
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        const data = await res.json();
        // Laravel paginator returns items in 'data', and meta in 'current_page', 'last_page'
        setBanners(data.data || []);
        setCurrentPage(data.current_page || 1);
        setLastPage(data.last_page || 1);
      }
    } catch (error) {
      console.error('Failed to fetch banners', error);
    }
  };

  const uploadToCloudinary = async (file: File) => {
    const cloudName = process.env.NEXT_PUBLIC_CLOUDINARY_CLOUD_NAME;
    const uploadPreset = process.env.NEXT_PUBLIC_CLOUDINARY_UPLOAD_PRESET;
    
    if (!cloudName || !uploadPreset) {
      alert("Cloudinary configuration missing in .env");
      return null;
    }

    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', uploadPreset);

    try {
      const res = await fetch(`https://api.cloudinary.com/v1_1/${cloudName}/image/upload`, {
        method: 'POST',
        body: formData,
      });
      
      const data = await res.json();
      return data.secure_url;
    } catch (error) {
      console.error("Cloudinary upload failed", error);
      return null;
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!imageFile && !editingBannerId) {
      alert("Please select an image");
      return;
    }

    setIsSubmitting(true);
    let imageUrl = imagePreviewUrl;
    
    if (imageFile) {
      setIsUploading(true);
      imageUrl = await uploadToCloudinary(imageFile);
      setIsUploading(false);

      if (!imageUrl) {
        alert("Image upload failed");
        setIsSubmitting(false);
        return;
      }
    }

    const payload = {
      title,
      image_url: imageUrl,
      action_url: actionUrl ? actionUrl : null,
      target_scope: targetScope,
      target_city_id: targetScope === 'city' ? targetCityId : null,
      target_salon_id: targetScope === 'salon' ? targetSalonId : null,
      start_date: startDate,
      end_date: endDate,
      is_active: true
    };

    try {
      const url = editingBannerId 
        ? `/api/superadmin/banners/${editingBannerId}` 
        : '/api/superadmin/banners';
      const method = editingBannerId ? 'PUT' : 'POST';

      const res = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (res.ok) {
        setIsModalOpen(false);
        resetForm();
        fetchBanners();
      } else {
        const data = await res.json();
        alert(data.message || `Failed to ${editingBannerId ? 'update' : 'create'} banner`);
      }
    } catch (error) {
      console.error(error);
      alert(`Error ${editingBannerId ? 'updating' : 'saving'} banner`);
    }
    
    setIsSubmitting(false);
  };

  const handleDelete = async (id: number) => {
    if (!confirm('Are you sure you want to delete this banner?')) return;
    
    try {
      const res = await fetch(`/api/superadmin/banners/${id}`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json'
        }
      });
      
      if (res.ok) {
        fetchBanners();
      }
    } catch (error) {
      console.error(error);
    }
  };

  const toggleActive = async (banner: Banner) => {
    try {
      const res = await fetch(`/api/superadmin/banners/${banner.id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ is_active: !banner.is_active })
      });
      
      if (res.ok) {
        fetchBanners();
      }
    } catch (error) {
      console.error(error);
    }
  };

  const handleEdit = (banner: Banner) => {
    setEditingBannerId(banner.id);
    setTitle(banner.title);
    setTargetScope(banner.target_scope);
    // @ts-ignore - The API returns target_city_id and target_salon_id under the hood but our interface didn't strongly type them all the way. Let's just use what we have or extract. Actually the API returns them properly if we updated it. We will use them if they exist.
    setTargetCityId(banner.target_city_id || '');
    // @ts-ignore
    setTargetSalonId(banner.target_salon_id || '');
    // Ensure date is formatted properly for input type="date"
    setStartDate(banner.start_date.split('T')[0]);
    setEndDate(banner.end_date.split('T')[0]);
    setActionUrl(banner.action_url || '');
    setImagePreviewUrl(banner.image_url);
    setImageFile(null);
    setIsModalOpen(true);
  };

  const resetForm = () => {
    setTitle('');
    setTargetScope('platform');
    setTargetCityId('');
    setTargetSalonId('');
    setStartDate('');
    setEndDate('');
    setActionUrl('');
    setImageFile(null);
    setImagePreviewUrl(null);
    setEditingBannerId(null);
  };

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h1 className={styles.title}>Banners Management</h1>
        <button className={styles.createButton} onClick={() => { resetForm(); setIsModalOpen(true); }}>
          + Create Banner
        </button>
      </div>

      <div style={{ display: 'flex', gap: '1rem', marginBottom: '20px', flexWrap: 'wrap' }}>
        <select 
          className={styles.select} 
          style={{ width: '200px' }}
          value={filterStatus} 
          onChange={(e) => { setFilterStatus(e.target.value); setCurrentPage(1); }}
        >
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="expired">Expired</option>
        </select>
        
        <select 
          className={styles.select} 
          style={{ width: '200px' }}
          value={filterScope} 
          onChange={(e) => { setFilterScope(e.target.value); setCurrentPage(1); }}
        >
          <option value="">All Scopes</option>
          <option value="platform">Platform-wide</option>
          <option value="city">Specific City</option>
          <option value="salon">Specific Salon</option>
        </select>

        <div style={{ width: '250px' }}>
          <AsyncSelect
            cacheOptions
            defaultOptions
            loadOptions={loadCities}
            onChange={(option: any) => { setFilterCityId(option ? option.value : ''); setCurrentPage(1); }}
            placeholder="Filter by city..."
            className="react-select-container"
            classNamePrefix="react-select"
            isClearable
          />
        </div>
      </div>

      <div className={styles.bannersGrid}>
        {banners.map(banner => (
          <div key={banner.id} className={styles.bannerCard}>
            <img src={banner.image_url} alt={banner.title} className={styles.bannerImage} />
            <div className={styles.bannerContent}>
              <h3 className={styles.bannerTitle}>{banner.title}</h3>
              <div className={styles.bannerMeta}>Scope: {banner.target_scope}</div>
              {banner.target_scope === 'city' && banner.target_city && <div className={styles.bannerMeta}>City: {banner.target_city}</div>}
              {banner.target_scope === 'salon' && banner.target_salon_id && <div className={styles.bannerMeta}>Salon ID: {banner.target_salon_id}</div>}
              <span className={`${styles.statusBadge} ${banner.is_active ? styles.statusActive : styles.statusInactive}`}>
                {banner.is_active ? 'Active' : 'Inactive'}
              </span>
            </div>
            <div className={styles.bannerActions}>
              <button 
                className={`${styles.actionButton} ${styles.editButton}`}
                onClick={() => handleEdit(banner)}
              >
                Edit
              </button>
              <button 
                className={`${styles.actionButton} ${styles.toggleButton}`}
                onClick={() => toggleActive(banner)}
              >
                {banner.is_active ? 'Deactivate' : 'Activate'}
              </button>
              <button 
                className={`${styles.actionButton} ${styles.deleteButton}`}
                onClick={() => handleDelete(banner.id)}
              >
                Delete
              </button>
            </div>
          </div>
        ))}
        {banners.length === 0 && <p>No banners found.</p>}
      </div>

      {lastPage > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', marginTop: '20px' }}>
          <button 
            disabled={currentPage === 1}
            onClick={() => setCurrentPage(p => p - 1)}
            style={{ padding: '8px 16px', borderRadius: '4px', border: '1px solid #ccc' }}
          >
            Previous
          </button>
          <span style={{ display: 'flex', alignItems: 'center' }}>
            Page {currentPage} of {lastPage}
          </span>
          <button 
            disabled={currentPage === lastPage}
            onClick={() => setCurrentPage(p => p + 1)}
            style={{ padding: '8px 16px', borderRadius: '4px', border: '1px solid #ccc' }}
          >
            Next
          </button>
        </div>
      )}

      {isModalOpen && (
        <div className={styles.modalOverlay}>
          <div className={styles.modal}>
            <h2 className={styles.modalTitle}>{editingBannerId ? 'Edit Banner' : 'Create New Banner'}</h2>
            <form onSubmit={handleSubmit}>
              <div className={styles.formGroup}>
                <label className={styles.label}>Title</label>
                <input 
                  type="text" 
                  className={styles.input} 
                  value={title} 
                  onChange={(e) => setTitle(e.target.value)} 
                  required 
                  maxLength={150}
                />
              </div>
              
              <div className={styles.formGroup}>
                <label className={styles.label}>Banner Image</label>
                <input 
                  type="file" 
                  className={styles.input} 
                  accept="image/*"
                  onChange={(e) => {
                    const file = e.target.files?.[0] || null;
                    setImageFile(file);
                    if (file) {
                      setImagePreviewUrl(URL.createObjectURL(file));
                    } else if (!editingBannerId) {
                      setImagePreviewUrl(null);
                    }
                  }} 
                  required={!editingBannerId} 
                />
                <small style={{ color: '#666', marginTop: '4px', display: 'block' }}>
                  Recommended size: 800x400px (2:1 ratio) for consistent carousel appearance.
                </small>
                {imagePreviewUrl && (
                  <div style={{ marginTop: '10px' }}>
                    <p style={{ fontSize: '14px', marginBottom: '4px', color: '#666' }}>Preview:</p>
                    <img 
                      src={imagePreviewUrl} 
                      alt="Banner Preview" 
                      style={{ 
                        width: '100%', 
                        height: 'auto',
                        maxHeight: '200px', 
                        objectFit: 'cover', 
                        borderRadius: '8px',
                        border: '1px solid #ddd'
                      }} 
                    />
                  </div>
                )}
              </div>

              <div className={styles.formGroup}>
                <label className={styles.label}>Action URL (Optional)</label>
                <input 
                  type="url" 
                  className={styles.input} 
                  value={actionUrl} 
                  onChange={(e) => setActionUrl(e.target.value)} 
                  placeholder="https://..."
                  maxLength={255}
                />
              </div>
              
              <div className={styles.formGroup}>
                <label className={styles.label}>Target Scope</label>
                <select 
                  className={styles.select} 
                  value={targetScope} 
                  onChange={(e) => setTargetScope(e.target.value as any)}
                >
                  <option value="platform">Platform-wide</option>
                  <option value="city">Specific City</option>
                  <option value="salon">Specific Salon</option>
                </select>
              </div>

              {targetScope === 'city' && (
                <div className={styles.formGroup}>
                  <label className={styles.label}>Select City</label>
                  <AsyncSelect
                    cacheOptions
                    defaultOptions
                    loadOptions={loadCities}
                    onChange={(option: any) => setTargetCityId(option ? option.value : '')}
                    placeholder="Search by city name..."
                    className="react-select-container"
                    classNamePrefix="react-select"
                  />
                  {!targetCityId && (
                    <input
                      tabIndex={-1}
                      autoComplete="off"
                      style={{ opacity: 0, height: 0, position: 'absolute' }}
                      required
                    />
                  )}
                </div>
              )}

              {targetScope === 'salon' && (
                <div className={styles.formGroup}>
                  <label className={styles.label}>Select Salon</label>
                  <AsyncSelect
                    cacheOptions
                    defaultOptions
                    loadOptions={loadSalons}
                    onChange={(option: any) => setTargetSalonId(option ? option.value : '')}
                    placeholder="Search by salon name..."
                    className="react-select-container"
                    classNamePrefix="react-select"
                  />
                  {!targetSalonId && (
                    <input
                      tabIndex={-1}
                      autoComplete="off"
                      style={{ opacity: 0, height: 0, position: 'absolute' }}
                      required
                    />
                  )}
                </div>
              )}

              <div className={styles.formGroup}>
                <label className={styles.label}>Start Date</label>
                <input 
                  type="date" 
                  className={styles.input} 
                  value={startDate} 
                  onChange={(e) => setStartDate(e.target.value)} 
                  required
                />
              </div>

              <div className={styles.formGroup}>
                <label className={styles.label}>End Date</label>
                <input 
                  type="date" 
                  className={styles.input} 
                  value={endDate} 
                  onChange={(e) => setEndDate(e.target.value)} 
                  required
                />
              </div>

              <div className={styles.modalActions}>
                <button 
                  type="button" 
                  className={styles.cancelButton} 
                  onClick={() => setIsModalOpen(false)}
                  disabled={isSubmitting}
                >
                  Cancel
                </button>
                <button 
                  type="submit" 
                  className={styles.submitButton}
                  disabled={isSubmitting}
                >
                  {isUploading ? 'Uploading Image...' : isSubmitting ? 'Saving...' : editingBannerId ? 'Update Banner' : 'Create Banner'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
