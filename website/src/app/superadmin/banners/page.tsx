'use client';

import { useState, useEffect, useCallback, useMemo } from 'react';
import AsyncSelect from 'react-select/async';
import Select from 'react-select';
import { useConfirm } from '@/components/admin/ui';
import styles from './banners.module.css';
import BannerStudio, { mediaKindFromUrl, type MediaKind } from './BannerStudio';

interface Banner {
  id: string;
  title: string;
  banner_type: 'static' | 'combo_discount' | 'specific_combo' | 'new_arrivals' | 'category_spotlight' | 'seasonal';
  config: any;
  image_url: string;
  media_kind?: MediaKind;
  action_url?: string;
  target_scope: 'platform' | 'city' | 'salon' | 'sub_area';
  target_city_id?: string;
  target_sub_area_id?: string;
  target_salon_id?: string;
  start_date: string;
  end_date: string;
  is_active: boolean;
  priority: number;
  impressions: number;
  clicks: number;
  city?: { id: string; name: string; state?: string } | null;
  subArea?: { id: string; name: string } | null;
  salon?: { id: string; name: string } | null;
}

type SelectOption = { label: string; value: string };

const toLocalISO = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

const addDaysISO = (iso: string, days: number) => {
  const d = new Date(`${iso}T00:00:00`);
  d.setDate(d.getDate() + days);
  return toLocalISO(d);
};

// The stored is_active flag does not know the calendar: a banner switched on
// for last week still has is_active = true today. Status is what the date says.
const bannerStatus = (banner: Banner, today: string) => {
  if (String(banner.end_date).slice(0, 10) < today) return 'expired';
  return banner.is_active ? 'active' : 'inactive';
};

export default function BannersPage() {
  const [banners, setBanners] = useState<Banner[]>([]);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isUploading, setIsUploading] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [editingBannerId, setEditingBannerId] = useState<string | null>(null);
  const [originalStartDate, setOriginalStartDate] = useState('');
  const [imagePreviewUrl, setImagePreviewUrl] = useState<string | null>(null);
  const [notice, setNotice] = useState('');
  const [confirm, confirmDialog] = useConfirm();
  
  // Filter & Pagination state
  const [filterStatus, setFilterStatus] = useState<string>('');
  const [filterScope, setFilterScope] = useState<string>('');
  const [filterType, setFilterType] = useState<string>('');
  const [filterCityId, setFilterCityId] = useState<string>('');
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [lastPage, setLastPage] = useState<number>(1);
  
  // Form state
  const [title, setTitle] = useState('');
  const [bannerType, setBannerType] = useState<Banner['banner_type']>('static');
  const [config, setConfig] = useState<any>({});
  const [targetScope, setTargetScope] = useState<Banner['target_scope']>('platform');
  const [targetCityId, setTargetCityId] = useState('');
  const [targetSubAreaId, setTargetSubAreaId] = useState('');
  const [targetSalonId, setTargetSalonId] = useState('');
  // react-select is controlled: the option objects are the real state, the ids
  // above are just what gets posted to the backend.
  const [targetCityOption, setTargetCityOption] = useState<SelectOption | null>(null);
  const [targetSubAreaOption, setTargetSubAreaOption] = useState<SelectOption | null>(null);
  const [targetSalonOption, setTargetSalonOption] = useState<SelectOption | null>(null);
  const [filterCityOption, setFilterCityOption] = useState<SelectOption | null>(null);
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [priority, setPriority] = useState<number>(0);
  const [actionUrl, setActionUrl] = useState('');
  const [imageFile, setImageFile] = useState<File | null>(null);
  // Static image or animated GIF/WebP. Owned here because it is what gets
  // posted as media_kind; BannerStudio only reports how it changed.
  const [mediaKind, setMediaKind] = useState<MediaKind>('image');

  const today = toLocalISO(new Date());
  // New banners: no dates before today. Editing: keep an already-live past start date selectable.
  const startMin = editingBannerId && originalStartDate && originalStartDate < today ? originalStartDate : today;
  const endMin = startDate ? addDaysISO(startDate, 1) : '';

  const handleStartDateChange = (value: string) => {
    setStartDate(value);
    if (endDate && value && endDate <= value) {
      setEndDate('');
    }
  };

  // Live Preview Data
  const [previewData, setPreviewData] = useState<any>(null);
  const [isPreviewLoading, setIsPreviewLoading] = useState(false);

  // Metadata caches
  const [catalog, setCatalog] = useState<{categories: any[]}>({ categories: [] });

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

  const loadSubAreas = async (inputValue: string) => {
    if (!targetCityId) return [];
    try {
      const res = await fetch(`/api/cities/${targetCityId}/sub-areas`);
      if (res.ok) {
        const data = await res.json();
        const subs = data.sub_areas || [];
        return subs
          .filter((sub: any) => sub.name.toLowerCase().includes(inputValue.toLowerCase()))
          .map((sub: any) => ({
            label: sub.name,
            value: sub.id
          }));
      }
      return [];
    } catch (error) {
      console.error('Failed to load sub-areas', error);
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

  const fetchCatalog = useCallback(async () => {
    try {
      const res = await fetch('/api/superadmin/catalog');
      if (res.ok) {
        setCatalog(await res.json());
      }
    } catch (error) {
      console.error('Failed to load catalog', error);
    }
  }, []);

  useEffect(() => {
    fetchCatalog();
  }, [fetchCatalog]);

  useEffect(() => {
    fetchBanners();
  }, [currentPage, filterStatus, filterScope, filterType, filterCityId]);

  const fetchBanners = async () => {
    try {
      const queryParams = new URLSearchParams({ page: currentPage.toString() });
      if (filterStatus) queryParams.append('status', filterStatus);
      if (filterScope) queryParams.append('target_scope', filterScope);
      if (filterType) queryParams.append('banner_type', filterType);
      if (filterCityId) queryParams.append('target_city_id', filterCityId);

      const res = await fetch(`/api/superadmin/banners?${queryParams.toString()}`, {
        headers: {
          'Accept': 'application/json'
        }
      });
      if (res.ok) {
        const data = await res.json();
        setBanners(data.data || []);
        setCurrentPage(data.current_page || 1);
        setLastPage(data.last_page || 1);
      }
    } catch (error) {
      console.error('Failed to fetch banners', error);
    }
  };

  // Live preview effect
  useEffect(() => {
    if (!isModalOpen) return;
    const fetchPreview = async () => {
      setIsPreviewLoading(true);
      try {
        const res = await fetch('/api/superadmin/banners/preview', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
          body: JSON.stringify({
            banner_type: bannerType,
            config,
            target_scope: targetScope,
            target_city_id: targetScope === 'city' || targetScope === 'sub_area' ? targetCityId : null,
            target_sub_area_id: targetScope === 'sub_area' ? targetSubAreaId : null,
            target_salon_id: targetScope === 'salon' ? targetSalonId : null,
          })
        });
        if (res.ok) {
          setPreviewData(await res.json());
        }
      } catch (error) {
        console.error('Preview failed', error);
      } finally {
        setIsPreviewLoading(false);
      }
    };
    
    // Debounce preview
    const timeout = setTimeout(fetchPreview, 500);
    return () => clearTimeout(timeout);
  }, [bannerType, config, targetScope, targetCityId, targetSubAreaId, targetSalonId, isModalOpen]);

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
    if (!imageFile && !editingBannerId && bannerType === 'static') {
      alert("Static banners require an image");
      return;
    }
    if (mediaKind === 'animated' && !imagePreviewUrl) {
      alert("An animated banner needs its GIF or WebP image");
      return;
    }
    if (!startDate || !endDate || endDate <= startDate) {
      alert("End date must be after the start date");
      return;
    }
    if (!editingBannerId && startDate < today) {
      alert("Start date cannot be before today");
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
      banner_type: bannerType,
      config,
      image_url: imageUrl,
      media_kind: mediaKind,
      action_url: actionUrl ? actionUrl : null,
      target_scope: targetScope,
      target_city_id: (targetScope === 'city' || targetScope === 'sub_area') ? targetCityId : null,
      target_sub_area_id: targetScope === 'sub_area' ? targetSubAreaId : null,
      target_salon_id: targetScope === 'salon' ? targetSalonId : null,
      start_date: startDate,
      end_date: endDate,
      priority,
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
        let errorMessage = data.message || `Failed to ${editingBannerId ? 'update' : 'create'} banner`;
        if (data.errors) {
          const messages = Object.values(data.errors).flat().join('\n');
          if (messages) errorMessage = messages;
        }
        alert(errorMessage);
      }
    } catch (error) {
      console.error(error);
      alert(`Error ${editingBannerId ? 'updating' : 'saving'} banner`);
    }
    
    setIsSubmitting(false);
  };

  const scopeLabel = (banner: Banner) => {
    if (banner.target_scope === 'platform') return 'every customer on the platform';
    if (banner.target_scope === 'city') return `customers in city ID ${banner.target_city_id}`;
    if (banner.target_scope === 'sub_area') return `customers in sub-area ID ${banner.target_sub_area_id}`;
    return 'customers of that one salon';
  };

  const handleDelete = async (banner: Banner) => {
    const ok = await confirm({
      title: `Delete “${banner.title}”?`,
      body: `This removes the banner for good. It was shown to ${scopeLabel(banner)}.`,
      confirmLabel: 'Delete banner',
      tone: 'danger',
    });
    if (!ok) return;

    setNotice('');
    try {
      const res = await fetch(`/api/superadmin/banners/${banner.id}`, {
        method: 'DELETE',
        headers: { 'Accept': 'application/json' }
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.message || 'Could not delete the banner.');
      }
      setNotice(`Deleted “${banner.title}”.`);
      fetchBanners();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Could not delete the banner.');
    }
  };

  const confirmToggleActive = async (banner: Banner) => {
    const hiding = banner.is_active;
    const ok = await confirm({
      title: hiding ? `Hide “${banner.title}”?` : `Show “${banner.title}”?`,
      body: hiding
        ? `It disappears from ${scopeLabel(banner)} straight away. The banner is kept, so you can bring it back.`
        : `It starts showing again in ${scopeLabel(banner)} from today.`,
      confirmLabel: hiding ? 'Hide banner' : 'Show banner',
    });
    if (!ok) return;

    setNotice('');
    try {
      const res = await fetch(`/api/superadmin/banners/${banner.id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ is_active: !banner.is_active })
      });

      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.message || 'Could not update the banner.');
      }
      setNotice(`“${banner.title}” is now ${hiding ? 'hidden' : 'showing'}.`);
      fetchBanners();
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'Could not update the banner.');
    }
  };

  const handleEdit = (banner: Banner) => {
    setEditingBannerId(banner.id);
    setTitle(banner.title);
    setBannerType(banner.banner_type);
    setConfig(banner.config || {});
    setTargetScope(banner.target_scope);
    setTargetCityId(banner.target_city_id || '');
    setTargetSubAreaId(banner.target_sub_area_id || '');
    setTargetSalonId(banner.target_salon_id || '');
    setTargetCityOption(
      banner.city
        ? { label: `${banner.city.name}${banner.city.state ? ` (${banner.city.state})` : ''}`, value: String(banner.city.id) }
        : banner.target_city_id
          ? { label: 'Selected City', value: banner.target_city_id }
          : null
    );
    setTargetSubAreaOption(
      banner.subArea
        ? { label: banner.subArea.name, value: String(banner.subArea.id) }
        : banner.target_sub_area_id
          ? { label: 'Selected Sub-Area', value: banner.target_sub_area_id }
          : null
    );
    setTargetSalonOption(
      banner.salon
        ? { label: banner.salon.name, value: String(banner.salon.id) }
        : banner.target_salon_id
          ? { label: 'Selected Salon', value: banner.target_salon_id }
          : null
    );
    setStartDate(banner.start_date.split('T')[0]);
    setEndDate(banner.end_date.split('T')[0]);
    setOriginalStartDate(banner.start_date.split('T')[0]);
    setPriority(banner.priority || 0);
    setActionUrl(banner.action_url || '');
    setImagePreviewUrl(banner.image_url);
    // The URL decides when it can — a legacy GIF row predates the column —
    // so editing one never presents it as a static image.
    setMediaKind(mediaKindFromUrl(banner.image_url) ?? banner.media_kind ?? 'image');
    setImageFile(null);
    setIsModalOpen(true);
  };

  const resetForm = () => {
    setTitle('');
    setBannerType('static');
    setConfig({});
    setTargetScope('platform');
    setTargetCityId('');
    setTargetSubAreaId('');
    setTargetSalonId('');
    setTargetCityOption(null);
    setTargetSubAreaOption(null);
    setTargetSalonOption(null);
    setStartDate('');
    setEndDate('');
    setPriority(0);
    setActionUrl('');
    setImageFile(null);
    setImagePreviewUrl(null);
    setMediaKind('image');
    setEditingBannerId(null);
    setOriginalStartDate('');
    setPreviewData(null);
  };

  // Helper for Specific Combo select options
  const serviceTemplateOptions = useMemo(() => {
    const opts: any[] = [];
    catalog.categories.forEach(cat => {
      cat.templates?.forEach((tpl: any) => {
        opts.push({ label: `${tpl.name} (${cat.name})`, value: tpl.id });
      });
    });
    return opts;
  }, [catalog]);

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
          style={{ width: '150px' }}
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
          style={{ width: '180px' }}
          value={filterType} 
          onChange={(e) => { setFilterType(e.target.value); setCurrentPage(1); }}
        >
          <option value="">All Banner Types</option>
          <option value="static">Static</option>
          <option value="combo_discount">Combo Discount</option>
          <option value="specific_combo">Specific Combo</option>
          <option value="new_arrivals">New Arrivals</option>
          <option value="category_spotlight">Category Spotlight</option>
          <option value="seasonal">Seasonal</option>
        </select>
        
        <select 
          className={styles.select} 
          style={{ width: '160px' }}
          value={filterScope} 
          onChange={(e) => { setFilterScope(e.target.value); setCurrentPage(1); }}
        >
          <option value="">All Scopes</option>
          <option value="platform">Platform-wide</option>
          <option value="city">Specific City</option>
          <option value="sub_area">Sub-Area</option>
          <option value="salon">Specific Salon</option>
        </select>

        <div style={{ width: '250px' }}>
          <AsyncSelect
            cacheOptions
            defaultOptions
            loadOptions={loadCities}
            value={filterCityOption}
            onChange={(option: SelectOption | null) => { setFilterCityOption(option); setFilterCityId(option ? option.value : ''); setCurrentPage(1); }}
            placeholder="Filter by city..."
            className="react-select-container"
            classNamePrefix="react-select"
            isClearable
          />
        </div>
      </div>

      {notice && (
        <p
          role="status"
          style={{ color: 'var(--text-body)', marginBottom: '1rem' }}
        >
          {notice}
        </p>
      )}

      <div className={styles.bannersGrid}>
        {banners.map(banner => (
          <div key={banner.id} className={styles.bannerCard}>
            <div style={{ position: 'relative' }}>
              <img src={banner.image_url || 'https://via.placeholder.com/600x240?text=Auto+Generated'} alt={banner.title} className={styles.bannerImage} />
              {/* Stacked so adding the media badge never shifts the type badge. */}
              <div style={{ position: 'absolute', top: 8, right: 8, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 4 }}>
                <div style={{ background: 'var(--surface-color)', padding: '2px 8px', borderRadius: 4, fontSize: '0.75rem', fontWeight: 600 }}>
                  {banner.banner_type.replace('_', ' ').toUpperCase()}
                </div>
                {(mediaKindFromUrl(banner.image_url) ?? banner.media_kind) === 'animated' && (
                  <span className={styles.animatedBadge}>ANIMATED</span>
                )}
              </div>
            </div>
            <div className={styles.bannerContent}>
              <h3 className={styles.bannerTitle}>{banner.title}</h3>
              <div className={styles.bannerMeta}>Scope: {banner.target_scope}</div>
              <div className={styles.bannerMeta}>Priority: {banner.priority}</div>
              <div className={styles.bannerMeta}>Impressions: {banner.impressions} | Clicks: {banner.clicks}</div>
              <span className={`${styles.statusBadge} ${bannerStatus(banner, today) === 'active' ? styles.statusActive : bannerStatus(banner, today) === 'expired' ? styles.statusExpired : styles.statusInactive}`}>
                {bannerStatus(banner, today) === 'expired' ? 'Expired' : banner.is_active ? 'Active' : 'Inactive'}
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
                onClick={() => confirmToggleActive(banner)}
              >
                {banner.is_active ? 'Deactivate' : 'Activate'}
              </button>
              <button 
                className={`${styles.actionButton} ${styles.deleteButton}`}
                onClick={() => handleDelete(banner)}
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
            style={{ padding: '8px 16px', borderRadius: '4px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--text-heading)' }}
          >
            Previous
          </button>
          <span style={{ display: 'flex', alignItems: 'center' }}>
            Page {currentPage} of {lastPage}
          </span>
          <button 
            disabled={currentPage === lastPage}
            onClick={() => setCurrentPage(p => p + 1)}
            style={{ padding: '8px 16px', borderRadius: '4px', border: '1px solid var(--border-strong)', background: 'var(--surface-color)', color: 'var(--text-heading)' }}
          >
            Next
          </button>
        </div>
      )}

      {isModalOpen && (
        <div className={styles.modalOverlay} style={{ padding: '20px' }}>
          <div className={styles.modal} style={{ maxWidth: '1100px', display: 'flex', gap: '2rem', padding: '0', background: 'transparent', boxShadow: 'none' }}>
            
            {/* LEFT SIDE: FORM */}
            <div style={{ flex: 1, background: 'var(--surface-color)', padding: '2rem', borderRadius: 'var(--radius-lg)', maxHeight: '90vh', overflowY: 'auto' }}>
              <h2 className={styles.modalTitle}>{editingBannerId ? 'Edit Banner' : 'Create New Banner'}</h2>
              <form onSubmit={handleSubmit}>
                <div className={styles.formGroup}>
                  <label className={styles.label}>Banner Type</label>
                  <select 
                    className={styles.select} 
                    value={bannerType} 
                    onChange={(e) => {
                      setBannerType(e.target.value as any);
                      setConfig({}); // Reset config on type change
                    }}
                  >
                    <option value="static">Static Image</option>
                    <option value="combo_discount">Combo Discount</option>
                    <option value="specific_combo">Specific Combo Spotlight</option>
                    <option value="new_arrivals">New Arrivals</option>
                    <option value="category_spotlight">Category Spotlight</option>
                    <option value="seasonal">Seasonal / Event</option>
                  </select>
                </div>

                <div className={styles.formGroup}>
                  <label className={styles.label}>Title (Internal / Fallback)</label>
                  <input 
                    type="text" 
                    className={styles.input} 
                    value={title} 
                    onChange={(e) => setTitle(e.target.value)} 
                    required 
                    maxLength={150}
                  />
                </div>

                {/* --- CONFIG FIELDS --- */}
                <div style={{ background: 'var(--bg-color)', padding: '1rem', borderRadius: 8, marginBottom: '1.25rem' }}>
                  <h4 style={{ margin: '0 0 1rem 0', fontSize: '0.9rem' }}>Type Configuration</h4>
                  
                  {bannerType === 'combo_discount' && (
                    <div className={styles.formGroup}>
                      <label className={styles.label}>Minimum Discount Percentage</label>
                      <input 
                        type="number" 
                        className={styles.input} 
                        value={config.min_discount_pct || 20} 
                        onChange={(e) => setConfig({...config, min_discount_pct: parseInt(e.target.value)})} 
                        min={1} max={99}
                      />
                    </div>
                  )}

                  {bannerType === 'specific_combo' && (
                    <div className={styles.formGroup}>
                      <label className={styles.label}>Services the Combo MUST contain</label>
                      <Select
                        isMulti
                        options={serviceTemplateOptions}
                        value={serviceTemplateOptions.filter(o => (config.service_template_ids || []).includes(o.value))}
                        onChange={(selected) => setConfig({...config, service_template_ids: selected.map((s: any) => s.value)})}
                        className="react-select-container"
                        classNamePrefix="react-select"
                      />
                    </div>
                  )}

                  {bannerType === 'new_arrivals' && (
                    <div className={styles.formGroup}>
                      <label className={styles.label}>"New" Window (Days)</label>
                      <input 
                        type="number" 
                        className={styles.input} 
                        value={config.window_days || 7} 
                        onChange={(e) => setConfig({...config, window_days: parseInt(e.target.value)})} 
                        min={1}
                      />
                    </div>
                  )}

                  {bannerType === 'category_spotlight' && (
                    <div className={styles.formGroup}>
                      <label className={styles.label}>Spotlight Category</label>
                      <select 
                        className={styles.select}
                        value={config.category_id || ''}
                        onChange={(e) => setConfig({...config, category_id: e.target.value})}
                      >
                        <option value="">Select Category...</option>
                        {catalog.categories.map(cat => (
                          <option key={cat.id} value={cat.id}>{cat.name}</option>
                        ))}
                      </select>
                    </div>
                  )}

                  {bannerType === 'seasonal' && (
                    <div className={styles.formGroup}>
                      <label className={styles.label}>Theme String</label>
                      <input 
                        type="text" 
                        className={styles.input} 
                        value={config.theme || ''} 
                        onChange={(e) => setConfig({...config, theme: e.target.value})} 
                        placeholder="e.g. Diwali, Valentine's"
                      />
                    </div>
                  )}

                  {['combo_discount', 'new_arrivals'].includes(bannerType) && (
                    <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: '0.85rem' }}>
                      <input 
                        type="checkbox" 
                        checked={config.auto_hide !== false} 
                        onChange={(e) => setConfig({...config, auto_hide: e.target.checked})} 
                      />
                      Auto-hide when no matching results are found
                    </label>
                  )}
                  {bannerType === 'static' && <p style={{ fontSize: '0.85rem', color: 'var(--text-body)', margin: 0 }}>Static banners require an image to be uploaded below.</p>}
                </div>
                {/* --- END CONFIG --- */}

                {/* TARGETING */}
                <div className={styles.formGroup}>
                  <label className={styles.label}>Target Scope</label>
                  <select 
                    className={styles.select} 
                    value={targetScope} 
                    onChange={(e) => {
                      setTargetScope(e.target.value as Banner['target_scope']);
                      setTargetCityId('');
                      setTargetSubAreaId('');
                      setTargetCityOption(null);
                      setTargetSubAreaOption(null);
                    }}
                  >
                    <option value="platform">Platform-wide</option>
                    <option value="city">Specific City</option>
                    <option value="sub_area">Specific Sub-Area</option>
                    {/* Only while editing a salon-scoped banner: new banners can no longer target one salon. */}
                    {editingBannerId && targetScope === 'salon' && <option value="salon">Specific Salon</option>}
                  </select>
                </div>

                {(targetScope === 'city' || targetScope === 'sub_area') && (
                  <div className={styles.formGroup}>
                    <label className={styles.label}>Select City</label>
                    <AsyncSelect
                      cacheOptions
                      defaultOptions
                      loadOptions={loadCities}
                      value={targetCityOption}
                      onChange={(option: SelectOption | null) => {
                        setTargetCityOption(option);
                        setTargetCityId(option ? option.value : '');
                        setTargetSubAreaOption(null);
                        setTargetSubAreaId(''); // Reset sub area if city changes
                      }}
                      placeholder="Search by city name..."
                      className="react-select-container"
                      classNamePrefix="react-select"
                    />
                  </div>
                )}

                {targetScope === 'sub_area' && targetCityId && (
                  <div className={styles.formGroup}>
                    <label className={styles.label}>Select Sub-Area</label>
                    <AsyncSelect
                      cacheOptions
                      defaultOptions
                      loadOptions={loadSubAreas}
                      value={targetSubAreaOption}
                      onChange={(option: SelectOption | null) => {
                        setTargetSubAreaOption(option);
                        setTargetSubAreaId(option ? option.value : '');
                      }}
                      placeholder="Search sub-areas in city..."
                      className="react-select-container"
                      classNamePrefix="react-select"
                    />
                  </div>
                )}

                {targetScope === 'salon' && (
                  <div className={styles.formGroup}>
                    <label className={styles.label}>Select Salon</label>
                    <AsyncSelect
                      cacheOptions
                      defaultOptions
                      loadOptions={loadSalons}
                      value={targetSalonOption}
                      onChange={(option: SelectOption | null) => {
                        setTargetSalonOption(option);
                        setTargetSalonId(option ? option.value : '');
                      }}
                      placeholder="Search by salon name..."
                      className="react-select-container"
                      classNamePrefix="react-select"
                    />
                  </div>
                )}

                <div style={{ display: 'flex', gap: '1rem' }}>
                  <div className={styles.formGroup} style={{ flex: 1 }}>
                    <label className={styles.label}>Start Date</label>
                    <input 
                      type="date" 
                      className={styles.input} 
                      value={startDate} 
                      min={startMin}
                      onChange={(e) => handleStartDateChange(e.target.value)} 
                      required
                    />
                  </div>
                  <div className={styles.formGroup} style={{ flex: 1 }}>
                    <label className={styles.label}>End Date</label>
                    <input 
                      type="date" 
                      className={styles.input} 
                      value={endDate} 
                      min={endMin}
                      onChange={(e) => setEndDate(e.target.value)} 
                      required
                    />
                  </div>
                </div>

                <div className={styles.formGroup}>
                  <label className={styles.label}>Priority (Lower = First)</label>
                  <input 
                    type="number" 
                    className={styles.input} 
                    value={priority} 
                    onChange={(e) => setPriority(parseInt(e.target.value) || 0)} 
                    onKeyDown={(e) => {
                      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
                        e.preventDefault();
                      }
                    }}
                    onWheel={(e) => (e.target as HTMLInputElement).blur()}
                    min={0}
                  />
                </div>

                <div className={styles.formGroup}>
                  <label className={styles.label}>Action URL (Optional for dynamic types)</label>
                  <input 
                    type="url" 
                    className={styles.input} 
                    value={actionUrl} 
                    onChange={(e) => setActionUrl(e.target.value)} 
                    placeholder="https://... or bookalook://..."
                    maxLength={255}
                  />
                </div>
                
                <div className={styles.formGroup}>
                  <label className={styles.label}>Banner Image (Optional for auto-generated types)</label>
                  <BannerStudio
                    file={imageFile}
                    previewUrl={imagePreviewUrl}
                    savedUrl={editingBannerId && !imageFile ? imagePreviewUrl : null}
                    title={title}
                    mediaKind={mediaKind}
                    onFile={setImageFile}
                    onPreview={setImagePreviewUrl}
                    onMediaKind={setMediaKind}
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

            {/* RIGHT SIDE: LIVE PREVIEW */}
            <div style={{ flex: '0 0 380px', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              <div style={{ background: 'var(--surface-color)', padding: '1.5rem', borderRadius: 'var(--radius-lg)' }}>
                <h3 style={{ fontSize: '1.1rem', marginBottom: '1rem', color: 'var(--text-heading)' }}>Live Resolution Preview</h3>
                <p style={{ fontSize: '0.85rem', color: 'var(--text-body)', marginBottom: '1rem', lineHeight: 1.5 }}>
                  This shows the data the customer app will receive based on the rules you have set on the left. If no salons qualify, dynamic banners will not appear.
                </p>

                {isPreviewLoading ? (
                  <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-body)' }}>Evaluating rules...</div>
                ) : !previewData ? (
                  <div style={{ padding: '2rem', textAlign: 'center', color: 'var(--text-body)' }}>Set targeting to see preview</div>
                ) : (
                  <div>
                    <div style={{ background: 'var(--accent-soft)', padding: '0.75rem', borderRadius: 8, color: 'var(--accent-color)', fontWeight: 600, fontSize: '0.9rem', marginBottom: '1rem' }}>
                      {previewData.summary}
                    </div>

                    {previewData.combos && previewData.combos.length > 0 && (
                      <div style={{ marginBottom: '1rem' }}>
                        <h4 style={{ fontSize: '0.85rem', textTransform: 'uppercase', color: 'var(--text-body)', marginBottom: '0.5rem' }}>Qualifying Combos</h4>
                        <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                          {previewData.combos.slice(0, 5).map((c: any) => (
                            <li key={c.id} style={{ background: 'var(--bg-color)', padding: '0.5rem', borderRadius: 4, fontSize: '0.8rem' }}>
                              <strong>{c.name}</strong> at {c.salon_name}
                            </li>
                          ))}
                          {previewData.combos.length > 5 && <li style={{ fontSize: '0.75rem', color: 'var(--text-body)' }}>+ {previewData.combos.length - 5} more</li>}
                        </ul>
                      </div>
                    )}

                    {previewData.salons && previewData.salons.length > 0 && (
                      <div>
                        <h4 style={{ fontSize: '0.85rem', textTransform: 'uppercase', color: 'var(--text-body)', marginBottom: '0.5rem' }}>Participating Salons</h4>
                        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.4rem' }}>
                          {previewData.salons.slice(0, 10).map((s: any) => (
                            <span key={s.id} style={{ background: 'var(--bg-color)', padding: '2px 6px', borderRadius: 4, fontSize: '0.75rem' }}>
                              {s.name}
                            </span>
                          ))}
                          {previewData.salons.length > 10 && <span style={{ fontSize: '0.75rem', color: 'var(--text-body)' }}>+ {previewData.salons.length - 10} more</span>}
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {confirmDialog}
    </div>
  );
}
